use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

fn collect_files_recursive(dir: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.filter_map(|e| e.ok()).collect();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let path = entry.path();
        let name = entry.file_name();
        let name_str = name.to_string_lossy();

        if name_str.starts_with('.') || name_str == "target" || name_str == "node_modules" {
            continue;
        }

        if path.is_dir() {
            collect_files_recursive(&path, out)?;
        } else if matches!(
            path.extension().and_then(|e| e.to_str()),
            Some("txt") | Some("tex") | Some("md")
        ) {
            out.push(path);
        }
    }
    Ok(())
}

/// Hand-rolled LaTeX stripper (no external crate). Not a full parser --
/// doesn't understand every LaTeX construct -- but handles the sources
/// of symbol-token noise that were dominating word-level training:
/// comments, math regions (dropped whole -- math isn't English prose),
/// reference/structural commands (dropped along with their arguments --
/// \cite{...}, \label{...}, \begin{...}, \usepackage{...}, ...), and
/// generic formatting commands (command stripped, argument content kept
/// -- \textbf{word} -> word).
fn strip_latex(text: &str) -> String {
    use std::collections::HashSet;

    let drop_commands: HashSet<&str> = [
        "cite", "citet", "citep", "citeauthor", "citeyear", "citealt",
        "ref", "eqref", "pageref", "label",
        "input", "include", "includegraphics",
        "bibliography", "bibliographystyle", "addbibresource", "printbibliography",
        "documentclass", "usepackage", "newcommand", "renewcommand",
        "DeclareMathOperator", "hypersetup", "definecolor", "geometry",
        "setlength", "newlength", "begin", "end", "newenvironment",
        "usetikzlibrary", "pgfplotsset", "maketitle", "tableofcontents",
        "footnote",
    ]
    .into_iter()
    .collect();

    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;

    while i < n {
        let c = chars[i];

        // Comment: unescaped % to end of line.
        if c == '%' {
            while i < n && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }

        // Escaped special characters: \%, \&, \$, \#, \_, \{, \}
        if c == '\\' && i + 1 < n && matches!(chars[i + 1], '%' | '&' | '$' | '#' | '_' | '{' | '}') {
            out.push(chars[i + 1]);
            i += 2;
            continue;
        }

        // Math mode: $...$ or $$...$$ -- dropped entirely.
        if c == '$' {
            let double = i + 1 < n && chars[i + 1] == '$';
            i += if double { 2 } else { 1 };
            while i < n {
                if chars[i] == '$' {
                    let close_double = i + 1 < n && chars[i + 1] == '$';
                    if double && close_double {
                        i += 2;
                        break;
                    } else if !double {
                        i += 1;
                        break;
                    }
                }
                i += 1;
            }
            continue;
        }

        // LaTeX line break "\\" -- must be consumed as a unit, before
        // the display-math check below, or the second backslash of the
        // pair can get misread as the start of "\[" when followed by an
        // optional-spacing argument like "\\[4pt]", causing everything
        // up to the next stray "\]" to be misidentified as math and
        // silently dropped.
        if c == '\\' && i + 1 < n && chars[i + 1] == '\\' {
            i += 2;
            // Consume an optional following [..] spacing argument, e.g.
            // the "[4pt]" in "\\[4pt]".
            if i < n && chars[i] == '[' {
                let mut depth = 1;
                i += 1;
                while i < n && depth > 0 {
                    if chars[i] == '[' {
                        depth += 1;
                    } else if chars[i] == ']' {
                        depth -= 1;
                    }
                    i += 1;
                }
            }
            out.push(' ');
            continue;
        }

        // Display math: \[...\]  and  \(...\) -- dropped entirely.
        if c == '\\' && i + 1 < n && (chars[i + 1] == '[' || chars[i + 1] == '(') {
            let close = if chars[i + 1] == '[' { ']' } else { ')' };
            i += 2;
            while i < n {
                if chars[i] == '\\' && i + 1 < n && chars[i + 1] == close {
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        // Command: backslash followed by a letter.
        if c == '\\' && i + 1 < n && chars[i + 1].is_alphabetic() {
            let start = i + 1;
            let mut j = start;
            while j < n && chars[j].is_alphabetic() {
                j += 1;
            }
            let name: String = chars[start..j].iter().collect();
            let mut k = j;
            if k < n && chars[k] == '*' {
                k += 1;
            }
            i = k;

            // Skip optional [..] arguments.
            while i < n && chars[i] == '[' {
                let mut depth = 1;
                i += 1;
                while i < n && depth > 0 {
                    if chars[i] == '[' {
                        depth += 1;
                    } else if chars[i] == ']' {
                        depth -= 1;
                    }
                    i += 1;
                }
            }

            if drop_commands.contains(name.as_str()) {
                // Drop all consecutive {...} argument groups entirely.
                while i < n && chars[i] == '{' {
                    let mut depth = 1;
                    i += 1;
                    while i < n && depth > 0 {
                        if chars[i] == '{' {
                            depth += 1;
                        } else if chars[i] == '}' {
                            depth -= 1;
                        }
                        i += 1;
                    }
                }
                continue;
            } else if i < n && chars[i] == '{' {
                // Unknown/formatting command: drop the command name,
                // unwrap the following {..} group (keep its content).
                let mut depth = 1;
                i += 1;
                let content_start = i;
                while i < n && depth > 0 {
                    if chars[i] == '{' {
                        depth += 1;
                    } else if chars[i] == '}' {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    i += 1;
                }
                let inner: String = chars[content_start..i].iter().collect();
                out.push_str(&strip_latex(&inner));
                if i < n {
                    i += 1; // skip closing brace
                }
                continue;
            } else {
                // Command with no following brace group (e.g. \item,
                // \alpha bare): just drop the command name itself.
                continue;
            }
        }

        // Any other backslash (line-break \\, stray \, etc.) -- drop
        // the backslash character alone; whatever follows is handled
        // normally on the next iteration.
        if c == '\\' {
            i += 1;
            continue;
        }

        // Bare grouping braces (not part of a command argument handled
        // above) -- drop the brace characters, keep inner content.
        if c == '{' || c == '}' {
            i += 1;
            continue;
        }

        // Non-breaking space -- treat as ordinary whitespace.
        if c == '~' {
            out.push(' ');
            i += 1;
            continue;
        }

        out.push(c);
        i += 1;
    }

    out
}

/// maximal run of alphanumeric/apostrophe characters; every other
/// non-whitespace character (punctuation, LaTeX backslash, braces, ...)
/// becomes its own single-character token; whitespace is a boundary
/// only, never a token itself.
///
/// This is deliberately crude -- it doesn't know LaTeX commands are
/// "\command{arg}" rather than "\", "command", "{", "arg", "}" as five
/// separate tokens. That's a real limitation, not an oversight: fixing
/// it means writing an actual LaTeX-aware tokenizer, which is its own
/// project. Flagged here rather than silently accepted.
pub fn tokenize_words(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut i = 0;

    while i < n {
        let c = chars[i];
        let is_word_char = c.is_alphanumeric() || c == '\'';
        // A hyphen counts as part of the word only when it's between
        // two word characters ("coarse-graining"), not when it's
        // standalone punctuation (a bullet dash, a minus sign, a
        // trailing dash) -- otherwise real hyphenated words were
        // getting split into two tokens plus a stray "-" token.
        let is_intraword_hyphen =
            c == '-' && !current.is_empty() && i + 1 < n && chars[i + 1].is_alphanumeric();

        if is_word_char || is_intraword_hyphen {
            current.push(c);
            i += 1;
        } else {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            if !c.is_whitespace() {
                tokens.push(c.to_string());
            }
            i += 1;
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

/// Punctuation-ish tokens that shouldn't get a preceding space when
/// rendering generated output back into readable text.
fn no_space_before(tok: &str) -> bool {
    matches!(tok, "." | "," | ";" | ":" | "!" | "?" | ")" | "]" | "}" | "'" | "-")
}

pub struct Corpus {
    pub vocab: Vec<String>,
    pub stoi: HashMap<String, usize>,
    pub tokens: Vec<usize>,
    pub unk_id: usize,
}

impl Corpus {
    /// Load and concatenate every .txt/.tex/.md file under `dir`,
    /// walking subdirectories recursively, sorted at every level for
    /// reproducible concatenation order.
    pub fn load_dir(dir: &Path, min_freq: usize) -> std::io::Result<Self> {
        let mut files = Vec::new();
        collect_files_recursive(dir, &mut files)?;
        files.sort();

        let mut text = String::new();
        for path in &files {
            if let Ok(contents) = fs::read_to_string(path) {
                let is_tex = path.extension().and_then(|e| e.to_str()) == Some("tex");
                if is_tex {
                    text.push_str(&strip_latex(&contents));
                } else {
                    text.push_str(&contents);
                }
                text.push('\n');
            }
        }
        eprintln!("loaded {} files, {} chars", files.len(), text.chars().count());
        Ok(Self::from_text(&text, min_freq))
    }

    /// `min_freq`: words occurring fewer than this many times in the
    /// corpus are folded into a single <unk> token, rather than each
    /// getting its own (barely-trained) embedding row and softmax
    /// output slot. This matters much more at word level than it did
    /// at char level: an unbounded word vocabulary on a corpus mixing
    /// prose, LaTeX macros, and code identifiers would otherwise run
    /// into the tens of thousands of entries, most seen only once.
    pub fn from_text(text: &str, min_freq: usize) -> Self {
        let raw_tokens = tokenize_words(text);

        let mut counts: HashMap<&str, usize> = HashMap::new();
        for t in &raw_tokens {
            *counts.entry(t.as_str()).or_insert(0) += 1;
        }

        let mut vocab: Vec<String> = counts
            .iter()
            .filter(|&(_, &c)| c >= min_freq)
            .map(|(w, _)| w.to_string())
            .collect();
        vocab.sort();
        vocab.push("<unk>".to_string());
        let unk_id = vocab.len() - 1;

        let stoi: HashMap<String, usize> =
            vocab.iter().enumerate().map(|(i, w)| (w.clone(), i)).collect();

        let tokens: Vec<usize> = raw_tokens
            .iter()
            .map(|t| *stoi.get(t.as_str()).unwrap_or(&unk_id))
            .collect();

        let unk_count = tokens.iter().filter(|&&t| t == unk_id).count();
        eprintln!(
            "vocab: {} words (min_freq={min_freq}) + <unk> -- {}/{} tokens ({:.1}%) are <unk>",
            vocab.len() - 1,
            unk_count,
            tokens.len(),
            100.0 * unk_count as f64 / tokens.len().max(1) as f64
        );

        Corpus { vocab, stoi, tokens, unk_id }
    }

    pub fn vocab_size(&self) -> usize {
        self.vocab.len()
    }

    /// Render a sequence of token ids back into readable text, using
    /// no_space_before() to avoid "word ." / "word ," artifacts.
    pub fn render(&self, ids: &[usize]) -> String {
        let mut out = String::new();
        for (i, &id) in ids.iter().enumerate() {
            let word = &self.vocab[id];
            if i > 0 && !no_space_before(word) {
                out.push(' ');
            }
            out.push_str(word);
        }
        out
    }

    /// (context, target) pairs: context = `block_size` preceding token ids,
    /// target = next token id.
    pub fn examples(&self, block_size: usize) -> Vec<(Vec<usize>, usize)> {
        let mut out = Vec::new();
        if self.tokens.len() <= block_size {
            return out;
        }
        for i in 0..(self.tokens.len() - block_size) {
            let ctx = self.tokens[i..i + block_size].to_vec();
            let target = self.tokens[i + block_size];
            out.push((ctx, target));
        }
        out
    }
}

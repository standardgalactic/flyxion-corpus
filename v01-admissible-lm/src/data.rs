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

        // Skip dotfiles/dotdirs (.git, .cargo, ...) and common build/
        // dependency directories -- noise, not corpus.
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

pub struct Corpus {
    pub vocab: Vec<char>,
    pub stoi: HashMap<char, usize>,
    pub tokens: Vec<usize>,
}

impl Corpus {
    /// Load and concatenate every .txt/.tex/.md file under `dir`,
    /// walking subdirectories recursively. Traversal order is sorted at
    /// each level (not just globally) so the same directory tree always
    /// concatenates in the same order, regardless of filesystem
    /// iteration order -- otherwise the resulting token stream (and
    /// therefore the training examples derived from it) wouldn't be
    /// reproducible across machines/runs.
    pub fn load_dir(dir: &Path) -> std::io::Result<Self> {
        let mut files = Vec::new();
        collect_files_recursive(dir, &mut files)?;
        files.sort();

        let mut text = String::new();
        for path in &files {
            if let Ok(contents) = fs::read_to_string(path) {
                text.push_str(&contents);
                text.push('\n');
            }
        }
        eprintln!("loaded {} files, {} chars", files.len(), text.chars().count());
        Ok(Self::from_text(&text))
    }

    pub fn from_text(text: &str) -> Self {
        let mut chars: Vec<char> = text.chars().collect::<std::collections::BTreeSet<_>>().into_iter().collect();
        chars.sort();
        let stoi: HashMap<char, usize> = chars.iter().enumerate().map(|(i, &c)| (c, i)).collect();
        let tokens = text.chars().map(|c| stoi[&c]).collect();
        Corpus { vocab: chars, stoi, tokens }
    }

    pub fn vocab_size(&self) -> usize {
        self.vocab.len()
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

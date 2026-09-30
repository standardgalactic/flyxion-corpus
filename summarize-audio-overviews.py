#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import urllib.request
from pathlib import Path


DEFAULT_MODEL = "granite4.1:3b"
OLLAMA_URL = "http://localhost:11434/api/generate"


INDIVIDUAL_PROMPT = """\
You are analyzing the transcript of an audio overview of one essay from a
larger body of research and writing.

Essay/audio overview: {name}

Produce a compact but information-dense summary of what this audio overview
says about the essay.

Preserve:
- the essay's central thesis or problem;
- important arguments and distinctions;
- distinctive terminology;
- mathematical, scientific, philosophical, or technical frameworks;
- examples, experiments, mechanisms, or case studies discussed;
- relationships explicitly made to other theories, works, or research programs;
- unresolved questions, qualifications, and limitations;
- particularly unusual or important claims.

This is an audio-overview transcript, not necessarily the essay itself.
Do not attribute claims to the original essay more strongly than the transcript
supports.

Do not introduce outside knowledge.
Do not invent relationships.
Do not write generic praise.
Do not spend space describing transcript formatting.
Do not discuss transcription quality unless it materially affects the content.

End with a line beginning:

KEYWORDS:

followed by 5-15 useful retrieval terms.

TRANSCRIPT:

{content}
"""


BATCH_PROMPT = """\
You are synthesizing summaries of audio overviews of essays from a single
large research and writing corpus.

Produce a structured synthesis of the material below.

Identify:
- recurring research programs and conceptual families;
- recurring arguments, mechanisms, and formal structures;
- mathematical, scientific, philosophical, and computational frameworks;
- distinctive terminology recurring across essays;
- essays that appear closely related;
- substantially overlapping arguments;
- important disagreements or tensions between essays;
- unusual outliers;
- ideas that appear to migrate from one domain into another;
- apparent development of concepts across different works, but only where
  the supplied summaries support this;
- unresolved questions and unfinished research directions.

Preserve essay names whenever making connections.

Distinguish:
1. relationships explicitly stated in the transcripts;
2. relationships inferred from substantive similarity.

Do not introduce outside knowledge.
Do not assume that shared vocabulary proves theoretical identity.

AUDIO-OVERVIEW SUMMARIES:

{content}
"""


GLOBAL_PROMPT = """\
You are constructing a global intellectual map of a large corpus of essays.
The evidence consists of summaries of audio-overview transcripts.

Write a detailed global synthesis explaining:

1. The major research programs represented in the essays.
2. The principal mathematical, scientific, philosophical, and computational
   frameworks.
3. Concepts and terminology recurring across otherwise different essays.
4. Major conceptual families and the essays belonging to each.
5. Cases where an idea appears to migrate from one domain into another.
6. Closely related essays and important differences between them.
7. Substantially duplicated or independently redeveloped ideas.
8. Important conceptual outliers.
9. Apparent historical or conceptual development, only where supported.
10. Open or weakly developed research directions.
11. Important tensions or apparent contradictions across the corpus.
12. An essay index grouped by conceptual family.
13. A concise account of what distinguishes the corpus as a whole.

Essay names are important evidence. Cite them throughout rather than
dissolving the corpus into anonymous themes.

Remember that the underlying sources are audio-overview transcripts rather
than the original essays. Do not silently attribute details to an original
essay when the evidence establishes only that its audio overview says them.

Do not introduce outside knowledge.
Do not assume repeated terminology proves theoretical identity.
Distinguish explicit relationships from relationships inferred from similarity.

BATCH SYNTHESES:

{content}
"""


def ollama_generate(model, prompt, timeout=1800):
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": True,
        "options": {
            "temperature": 0.2,
        },
    }).encode("utf-8")

    request = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    chunks = []

    with urllib.request.urlopen(request, timeout=timeout) as response:
        for raw_line in response:
            if not raw_line.strip():
                continue

            event = json.loads(raw_line.decode("utf-8"))
            chunk = event.get("response", "")

            if chunk:
                # Tee Granite's output live to the terminal.
                print(chunk, end="", flush=True)
                chunks.append(chunk)

    print()
    print()

    return "".join(chunks).strip()


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("_")


def file_hash(path):
    h = hashlib.sha256()

    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)

    return h.hexdigest()


def read_text(path):
    return path.read_text(
        encoding="utf-8",
        errors="replace",
    )


def find_transcripts(root):
    """
    Find every .txt file beneath the input directory.

    Files may be at arbitrary directory depths.
    """

    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix.lower() == ".txt"
    )


def transcript_name(root, path):
    """
    Use the relative path, without .txt, as the canonical identity.

    Example:

        corpus/cosmology/smoothness-paradox.txt

    becomes:

        cosmology/smoothness-paradox

    This prevents identically named transcripts in different directories
    from colliding.
    """

    rel = path.relative_to(root)
    return str(rel.with_suffix(""))


def transcript_output_name(root, path):
    """
    Produce a filesystem-safe output filename while retaining enough of the
    relative path to distinguish transcripts.

    foo/bar/baz.txt -> foo__bar__baz
    """

    rel = path.relative_to(root).with_suffix("")

    return safe_name(
        "__".join(rel.parts)
    )


def summarize_individual(root, path, outdir, model):
    name = transcript_name(root, path)
    digest = file_hash(path)

    basename = transcript_output_name(root, path)

    summary_path = (
        outdir
        / "transcripts"
        / f"{basename}.md"
    )

    metadata_path = (
        outdir
        / "transcripts"
        / f"{basename}.json"
    )

    # Resume support.
    #
    # If this exact transcript has already been summarized with this model,
    # reuse the existing result.
    if summary_path.exists() and metadata_path.exists():
        try:
            metadata = json.loads(
                metadata_path.read_text(
                    encoding="utf-8"
                )
            )

            if (
                metadata.get("sha256") == digest
                and metadata.get("model") == model
            ):
                print(f"SKIP {name}")
                return name, summary_path

        except Exception:
            pass

    content = read_text(path)

    if not content.strip():
        print(f"EMPTY {name}")
        return None

    prompt = INDIVIDUAL_PROMPT.format(
        name=name,
        content=content,
    )

    print(f"SUMMARIZE {name}")

    summary = ollama_generate(
        model,
        prompt,
    )

    summary_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    summary_path.write_text(
        f"# {name}\n\n{summary}\n",
        encoding="utf-8",
    )

    metadata_path.write_text(
        json.dumps(
            {
                "transcript": name,
                "source": str(path),
                "sha256": digest,
                "model": model,
                "characters": len(content),
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    return name, summary_path


def make_batches(items, max_chars):
    batches = []
    current = []
    current_size = 0

    for name, text in items:
        block = (
            f"\n\n"
            f"===== AUDIO OVERVIEW: {name} =====\n\n"
            f"{text}"
        )

        if (
            current
            and current_size + len(block) > max_chars
        ):
            batches.append(current)
            current = []
            current_size = 0

        current.append((name, text))
        current_size += len(block)

    if current:
        batches.append(current)

    return batches


def synthesize_batches(
    transcript_summaries,
    outdir,
    model,
    max_chars,
):
    batches = make_batches(
        transcript_summaries,
        max_chars,
    )

    results = []

    batch_dir = outdir / "batches"
    batch_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    for i, batch in enumerate(
        batches,
        start=1,
    ):
        path = (
            batch_dir
            / f"batch-{i:03d}.md"
        )

        metadata_path = (
            batch_dir
            / f"batch-{i:03d}.json"
        )

        content = "\n\n".join(
            (
                f"===== AUDIO OVERVIEW: "
                f"{name} =====\n{text}"
            )
            for name, text in batch
        )

        digest = hashlib.sha256(
            content.encode("utf-8")
        ).hexdigest()

        # Resume support for batch synthesis.
        if path.exists() and metadata_path.exists():
            try:
                metadata = json.loads(
                    metadata_path.read_text(
                        encoding="utf-8"
                    )
                )

                if (
                    metadata.get("sha256") == digest
                    and metadata.get("model") == model
                ):
                    print(
                        f"SKIP batch "
                        f"{i}/{len(batches)}"
                    )

                    results.append(
                        read_text(path)
                    )

                    continue

            except Exception:
                pass

        print(
            f"SYNTHESIZE batch "
            f"{i}/{len(batches)} "
            f"({len(batch)} audio overviews)"
        )

        result = ollama_generate(
            model,
            BATCH_PROMPT.format(
                content=content
            ),
        )

        path.write_text(
            f"# Batch {i}\n\n{result}\n",
            encoding="utf-8",
        )

        metadata_path.write_text(
            json.dumps(
                {
                    "batch": i,
                    "transcripts": [
                        name
                        for name, _ in batch
                    ],
                    "sha256": digest,
                    "model": model,
                },
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

        results.append(result)

    return results


def global_synthesis(
    batch_results,
    outdir,
    model,
):
    content = "\n\n".join(
        (
            f"===== BATCH {i} =====\n\n"
            f"{text}"
        )
        for i, text in enumerate(
            batch_results,
            start=1,
        )
    )

    digest = hashlib.sha256(
        content.encode("utf-8")
    ).hexdigest()

    output = (
        outdir
        / "GLOBAL_SUMMARY.md"
    )

    metadata_path = (
        outdir
        / "GLOBAL_SUMMARY.json"
    )

    # The global synthesis can also be resumed.
    if output.exists() and metadata_path.exists():
        try:
            metadata = json.loads(
                metadata_path.read_text(
                    encoding="utf-8"
                )
            )

            if (
                metadata.get("sha256") == digest
                and metadata.get("model") == model
            ):
                print(
                    "SKIP global synthesis "
                    "(unchanged)"
                )

                return output

        except Exception:
            pass

    print("GENERATE global synthesis")

    result = ollama_generate(
        model,
        GLOBAL_PROMPT.format(
            content=content
        ),
    )

    output.write_text(
        "# Global Audio-Overview Synthesis\n\n"
        + result
        + "\n",
        encoding="utf-8",
    )

    metadata_path.write_text(
        json.dumps(
            {
                "sha256": digest,
                "model": model,
                "batches": len(batch_results),
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    return output


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Hierarchically summarize a corpus "
            "of essay audio-overview transcripts."
        )
    )

    parser.add_argument(
        "input",
        nargs="?",
        default="transcripts",
        help=(
            "Directory containing .txt "
            "audio-overview transcripts"
        ),
    )

    parser.add_argument(
        "--output",
        default="audio-overview-summary",
        help=(
            "Directory for summaries "
            "and intermediate results"
        ),
    )

    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=(
            f"Ollama model "
            f"(default: {DEFAULT_MODEL})"
        ),
    )

    parser.add_argument(
        "--batch-chars",
        type=int,
        default=60000,
        help=(
            "Approximate maximum characters "
            "of transcript summaries per batch"
        ),
    )

    args = parser.parse_args()

    root = Path(args.input)
    outdir = Path(args.output)

    if not root.exists():
        raise SystemExit(
            f"Input directory does not exist: "
            f"{root}"
        )

    if not root.is_dir():
        raise SystemExit(
            f"Input is not a directory: {root}"
        )

    outdir.mkdir(
        parents=True,
        exist_ok=True,
    )

    paths = find_transcripts(root)

    print(
        f"Found {len(paths)} "
        f"audio-overview transcripts."
    )
    print(f"Model: {args.model}")
    print(f"Input: {root}")
    print(f"Output: {outdir}")
    print()

    if not paths:
        raise SystemExit(
            "No .txt transcripts found."
        )

    summaries = []

    for n, path in enumerate(
        paths,
        start=1,
    ):
        print(
            f"[{n}/{len(paths)}] ",
            end="",
        )

        try:
            result = summarize_individual(
                root,
                path,
                outdir,
                args.model,
            )

            if result is None:
                continue

            name, summary_path = result

            summaries.append(
                (
                    name,
                    read_text(summary_path),
                )
            )

        except Exception as exc:
            print(
                f"ERROR {path}: {exc}"
            )

    if not summaries:
        raise SystemExit(
            "No summaries were produced."
        )

    print()
    print(
        "Transcript summaries available: "
        f"{len(summaries)}"
    )
    print()

    batches = synthesize_batches(
        summaries,
        outdir,
        args.model,
        args.batch_chars,
    )

    print()

    final_path = global_synthesis(
        batches,
        outdir,
        args.model,
    )

    print()
    print("Finished.")
    print(
        f"Global summary: {final_path}"
    )


if __name__ == "__main__":
    main()

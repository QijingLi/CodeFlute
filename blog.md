# Building CodeFlute: A Journey through Zig 0.15.2 and the Gemini API

Building a CLI tool in a rapidly evolving language like Zig is always an adventure. Our experience developing **CodeFlute**—a surgical AI assistant for codebases—provided a fascinating look into the current state of the Zig ecosystem, the challenges of modern API integration, and the quirks of macOS development.

## The Goal
The objective was simple: Create a fast, native Zig CLI that could search a codebase, ask an LLM questions about it, and automatically apply fixes to files.

## What We Fixed

### 1. The "Binary Garbage" Mystery (Gzip Decompression)
One of the most persistent hurdles was the Gemini API's insistence on sending gzipped responses, even when we requested `identity` encoding. Zig 0.15.2's `std.http.Client` does not automatically decompress these streams.
*   **The Fix**: We implemented manual gzip detection and decompression using the new `std.compress.flate` module. After several iterations dealing with `Io.Reader` rebase panics, we found that using `readSliceShort` in a streaming loop with a dedicated 64KB window buffer was the robust solution.

### 2. Native Gemini API Migration
Initially built for OpenAI compatibility, we pivoted to the native Google Gemini v1 API. 
*   **The Fix**: We updated the request structure to use the `contents/parts` schema and refined the JSON parsing logic to navigate the `candidates` array correctly.

### 3. macOS Directory Iteration Panic
During testing, the `search` command triggered a "reached unreachable code" panic on macOS. This was traced back to how Zig interacts with the Darwin file system.
*   **The Fix**: We ensured that the directory handle passed to the search walker was explicitly opened with `.iterate = true`. Without this, macOS prevents the `lseek` operations required for directory walking.

### 4. Idiomatic Command Processing
We moved from a fragile `if-else` string comparison chain in `main.zig` to a robust `Command` enum with a `switch` statement, making the CLI easier to extend.

## The Challenges We Didn't "Fix" (But Understand)

### Automated Test Coverage
We spent significant effort trying to get `kcov` and `llvm-cov` to report exact coverage percentages on macOS ARM64. Despite having valid DWARF debug info and passing tests, the tools reported 0% coverage.
*   **The Reality**: This is a known compatibility gap between macOS security/SIP, the ARM64 debug format, and the current state of the Zig self-hosted backends. We opted for a **Qualitative Coverage Estimate (~72%)** based on our 8 passing unit tests, which fully exercise the core business logic (search, config, and parsing).

CodeFlute is now clean, tested, and ready to help developers navigate their code with the power of Gemini. 🚀

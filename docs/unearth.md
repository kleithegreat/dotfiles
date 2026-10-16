# Unearth

## Intent

- Idle cost is the constraint: having semantic search must not change the
  laptop's idle battery. Nothing in unearth touches the NVIDIA GPU, so
  `llama-cpp` stays a CPU build: a CUDA or Vulkan context keeps the dGPU out
  of runtime suspend (see [[nvidia]]).
- The model is resident only around use. `llama-server --sleep-idle-seconds`
  unloads it and blocks without polling; a request reloads it. No socket
  activation, no second process.
- Embedding runs only on AC. The indexer checks between files and leaves the
  rest for the next hourly run on AC; nothing is queued separately.
- Search never waits on the model before showing something: keyword hits come
  from FTS5 without the server, then the fused ranking replaces them.
- Scope is documents: plain-text formats and PDFs. Code would need its own
  index and prompt (`task: code retrieval`) so it doesn't drown documents;
  images and audio need the 555 MB mmproj encoder, which a query never loads.

## Quirks

### A model or prompt change needs a fresh index
The index records no model identity. New query vectors score against old
document vectors without any error, and results just get worse. After changing
the GGUF or either prompt prefix, delete `~/.local/state/unearth/index.db` and
let the indexer rebuild it.

### Indexing speed is the model, not the build
EmbeddingGemma 2 embeds roughly 300–600 tokens/s on the laptop's CPU, so a
first index runs for tens of minutes. Rebuilding llama.cpp without OpenBLAS,
flash attention and smaller batches were all measured with `llama-bench`; none
moved it meaningfully. The real lever is the GPU, which the Intent excludes.

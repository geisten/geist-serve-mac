// Models — the curated list, compiled in. Same six GGUFs as geistlib's
// docs/MODELS.md; SHA-256 are the HuggingFace LFS oids (the three that
// geistlib pins in its Makefile match). Bumping a model means changing
// the line here, nothing else.
import Foundation

struct CuratedModel: Identifiable, Hashable {
    let id: String       // menu + defaults key
    let name: String     // as shown
    let file: String     // file name on disk
    let url: URL
    let bytes: Int64
    let sha256: String
    let minRAMGB: Int
    let note: String

    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

enum Models {
    static let defaultID = "gemma4-e2b"

    static let curated: [CuratedModel] = [
        .init(id: "gemma4-e2b", name: "Gemma 4 E2B", file: "gemma-4-E2B-it-Q4_K_M.gguf",
              url: URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
              bytes: 3_106_738_272, sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
              minRAMGB: 8, note: "Google, instruction-tuned. The default: good answers on an 8 GB Mac."),
        .init(id: "gemma4-e4b", name: "Gemma 4 E4B", file: "gemma-4-E4B-it-Q4_K_M.gguf",
              url: URL(string: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
              bytes: 4_977_171_584, sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87",
              minRAMGB: 16, note: "Bigger Gemma 4; wants 16 GB."),
        .init(id: "qwen35-0.8b", name: "Qwen3.5 0.8B", file: "Qwen3.5-0.8B-Q8_0.gguf",
              url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q8_0.gguf")!,
              bytes: 811_843_840, sha256: "0ad885ffd4bb022fc4f0d33a3308fa108ef8613159d3b3a67e23abca056b7a6c",
              minRAMGB: 4, note: "Small and quick."),
        .init(id: "qwen3-0.6b", name: "Qwen3 0.6B", file: "Qwen3-0.6B-Q8_0.gguf",
              url: URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf")!,
              bytes: 639_446_688, sha256: "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031",
              minRAMGB: 4, note: "Smallest Qwen."),
        .init(id: "bitnet-2b", name: "BitNet b1.58 2B", file: "bitnet-b1.58-2B-4T-i2_s.gguf",
              url: URL(string: "https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf")!,
              bytes: 1_187_801_280, sha256: "4221b252fdd5fd25e15847adfeb5ee88886506ba50b8a34548374492884c2162",
              minRAMGB: 4, note: "Microsoft's ternary model; the engine's specialty."),
        .init(id: "smollm2-360m", name: "SmolLM2 360M", file: "smollm2-360m-instruct-q8_0.gguf",
              url: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf")!,
              bytes: 386_404_992, sha256: "48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201",
              minRAMGB: 2, note: "Tiny; for trying the setup."),
    ]

    static func byID(_ id: String) -> CuratedModel? { curated.first { $0.id == id } }
}

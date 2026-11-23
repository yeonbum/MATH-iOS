// iOS port of SolveMate's existing mtmd + llama.cpp logic.
// Model files (LLM GGUF and Qwen3-VL mmproj) are unchanged.
// This file intentionally uses only exported llama.cpp/mtmd C APIs, NOT JNI or common/chat.h.
#include "MateBridge.h"
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <llama.h>
#include <mtmd.h>
#include <mtmd-helper.h>
#include <ggml.h>

namespace {
std::mutex mutex_;
std::atomic_bool cancelled{false};
std::once_flag backend_once;
llama_model *model = nullptr;
llama_context *ctx = nullptr;
mtmd_context *vision = nullptr;
llama_pos chat_pos = 0;
bool chat_ready = false;
int context_limit = 2048;
std::string model_path, vision_path;
thread_local std::string result;

const char* success(std::string value) { result = std::move(value); return result.c_str(); }
const char* failed(const char *message) { return success(std::string("ERROR: ") + message); }

bool file_exists(const char *path) {
    return path && std::ifstream(path, std::ios::binary).good();
}

void unload_locked() {
    chat_ready = false;
    chat_pos = 0;
    if (vision) { mtmd_free(vision); vision = nullptr; }
    if (ctx) { llama_free(ctx); ctx = nullptr; }
    if (model) { llama_model_free(model); model = nullptr; }
    model_path.clear(); vision_path.clear();
}

using Chunks = std::unique_ptr<mtmd_input_chunks, decltype(&mtmd_input_chunks_free)>;
using Batch = std::unique_ptr<llama_batch_ext, decltype(&llama_batch_ext_free)>;
using Sampler = std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)>;

size_t valid_utf8_prefix(const std::string &s) {
    size_t i = 0;
    while (i < s.size()) {
        unsigned char head = static_cast<unsigned char>(s[i]);
        size_t length = head <= 0x7f ? 1 : head >= 0xc2 && head <= 0xdf ? 2 :
                        head >= 0xe0 && head <= 0xef ? 3 : head >= 0xf0 && head <= 0xf4 ? 4 : 0;
        if (!length) throw std::runtime_error("Invalid UTF-8 output");
        if (i + length > s.size()) break;
        for (size_t k=1; k<length; ++k) {
            if ((static_cast<unsigned char>(s[i+k]) & 0xc0) != 0x80) {
                throw std::runtime_error("Invalid UTF-8 continuation");
            }
        }
        i += length;
    }
    return i;
}

std::string piece(const llama_vocab *vocab, llama_token token) {
    std::vector<char> buffer(256);
    int n = llama_token_to_piece(vocab, token, buffer.data(), static_cast<int32_t>(buffer.size()), 0, false);
    if (n < 0) {
        buffer.resize(static_cast<size_t>(-n));
        n = llama_token_to_piece(vocab, token, buffer.data(), static_cast<int32_t>(buffer.size()), 0, false);
    }
    if (n < 0) throw std::runtime_error("token_to_piece failed");
    return std::string(buffer.data(), static_cast<size_t>(n));
}

Sampler make_sampler() {
    Sampler sampler(llama_sampler_chain_init(llama_sampler_chain_default_params()), &llama_sampler_free);
    if (!sampler) throw std::runtime_error("sampler initialization failed");
    const llama_vocab *vocab = llama_model_get_vocab(model);
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_penalties(
            llama_vocab_n_tokens(vocab), 64, 1.0f, 0.0f, 1.5f));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_k(20));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_p(0.8f, 1));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    return sampler;
}

// This ChatML wrapper is Qwen3-VL-specific, unlike common/chat.h on Android.
// Validate tokenization against the model's own chat template on first macOS CI/device run.
std::string initial_prompt(const std::string &question) {
    return "<|im_start|>user\n" + std::string(mtmd_default_marker()) + question +
           "<|im_end|>\n<|im_start|>assistant\n";
}
std::string next_prompt(const std::string &question) {
    return "<|im_end|>\n<|im_start|>user\n" + question +
           "<|im_end|>\n<|im_start|>assistant\n";
}

std::vector<llama_token> tokenize(const std::string &prompt) {
    const llama_vocab *vocab = llama_model_get_vocab(model);
    std::vector<llama_token> tokens(prompt.size() + 16);
    int n = llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                           tokens.data(), static_cast<int32_t>(tokens.size()), false, true);
    if (n < 0) {
        tokens.resize(static_cast<size_t>(-n));
        n = llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                           tokens.data(), static_cast<int32_t>(tokens.size()), false, true);
    }
    if (n <= 0) throw std::runtime_error("tokenization failed");
    tokens.resize(static_cast<size_t>(n));
    return tokens;
}

std::string decode_tokens(llama_pos &pos, int max_tokens,
                          mate_token_callback callback, void *user_data) {
    const llama_vocab *vocab = llama_model_get_vocab(model);
    auto sampler = make_sampler();
    Batch batch(llama_batch_ext_init(ctx), &llama_batch_ext_free);
    if (!batch) return "ERROR: decode batch initialization failed";
    std::string pending;
    int count = 0;
    bool eos = false;
    for (; count < max_tokens && pos + 1 < context_limit; ++count) {
        if (cancelled.load()) { chat_ready = false; return "CANCELLED"; }
        llama_token tok = llama_sampler_sample(sampler.get(), ctx, -1);
        if (tok == LLAMA_TOKEN_NULL) return "ERROR: null token";
        if (llama_vocab_is_eog(vocab, tok)) { eos = true; break; }
        if (!llama_vocab_is_control(vocab, tok)) {
            pending += piece(vocab, tok);
            const size_t prefix = valid_utf8_prefix(pending);
            if (prefix && callback) {
                const std::string part = pending.substr(0, prefix);
                callback(part.c_str(), user_data);
                pending.erase(0, prefix);
            }
        }
        llama_batch_ext_clear(batch.get());
        int idx = llama_batch_ext_add_token(batch.get(), 0, tok);
        if (idx < 0 || !llama_batch_ext_set_pos(batch.get(), idx, &pos) ||
            !llama_batch_ext_set_output_logits(batch.get(), idx, true)) {
            return "ERROR: decode batch construction failed";
        }
        if (llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch.get()) != 0) {
            return "ERROR: token decode failed";
        }
        ++pos;
    }
    chat_ready = true;
    return std::string("OK: generated=") + std::to_string(count) + (eos ? "; EOS" : "; limit");
}

std::string first_locked(const char *image_path, const char *question, int max_tokens,
                         mate_token_callback callback, void *user_data) {
    if (!model || !ctx || !vision) return "ERROR: Model not loaded";
    if (!file_exists(image_path)) return "ERROR: Image file not found";
    if (!question || !*question) return "ERROR: Empty question";
    if (max_tokens < 1 || max_tokens > 2048) return "ERROR: Invalid token limit";
    cancelled = false;
    chat_ready = false;
    chat_pos = 0;
    llama_memory_clear(llama_get_memory(ctx), true);

    const auto file_opts = mtmd_helper_init_opt_default();
    auto file = mtmd_helper_bitmap_init_from_file(vision, image_path, false, file_opts);
    if (!file.bitmap) return "ERROR: Image decode failed";
    std::unique_ptr<mtmd_bitmap, decltype(&mtmd_bitmap_free)> bitmap(file.bitmap, &mtmd_bitmap_free);
    if (file.video_ctx) { mtmd_helper_video_free(file.video_ctx); return "ERROR: Video is not supported"; }

    std::string formatted = initial_prompt(question);
    std::string marker = mtmd_default_marker();
    const size_t at = formatted.find(marker);
    if (at == std::string::npos) return "ERROR: Missing image marker";
    std::string before = formatted.substr(0, at);
    std::string after = formatted.substr(at + marker.size());
    mtmd_input_text txt1{before.data(), before.size(), false, true};
    mtmd_input_text txt2{after.data(), after.size(), false, true};
    mtmd_input_part a{&txt1, nullptr}, b{nullptr, bitmap.get()}, c{&txt2, nullptr};
    const mtmd_input_part *parts[] = {&a, &b, &c};
    Chunks chunks(mtmd_input_chunks_init(), &mtmd_input_chunks_free);
    if (!chunks) return "ERROR: mtmd chunk allocation failed";
    if (mtmd_tokenize_from_parts(vision, chunks.get(), parts, 3, true) != 0) {
        return "ERROR: Vision tokenization failed";
    }
    if (mtmd_helper_get_n_tokens(chunks.get()) + 2 >= static_cast<size_t>(context_limit)) {
        return "ERROR: Context too small for image";
    }
    llama_pos pos = 0;
    for (size_t i = 0; i < mtmd_input_chunks_size(chunks.get()); ++i) {
        if (cancelled.load()) return "CANCELLED";
        const mtmd_input_chunk *chunk = mtmd_input_chunks_get(chunks.get(), i);
        int rc = 0;
        if (mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_IMAGE) {
            rc = mtmd_encode_chunk(vision, chunk);
            if (rc) return "ERROR: Vision encoding failed";
            float *embeddings = mtmd_get_output_embd(vision);
            if (!embeddings) return "ERROR: Vision output unavailable";
            rc = mtmd_helper_decode_image_chunk(vision, ctx, chunk, embeddings,
                                                 pos, 0, 512, &pos, nullptr, nullptr);
        } else {
            rc = mtmd_helper_eval_chunk_single(vision, ctx, chunk, pos, 0, 512,
                                                i + 1 == mtmd_input_chunks_size(chunks.get()), &pos);
        }
        if (rc) return "ERROR: Image/text prefill failed";
    }
    chunks.reset(); bitmap.reset();
    const std::string result = decode_tokens(pos, max_tokens, callback, user_data);
    if (result.rfind("OK:", 0) == 0) chat_pos = pos;
    return result;
}

std::string follow_locked(const char *question, int max_tokens,
                          mate_token_callback callback, void *user_data) {
    if (!model || !ctx || !vision || !chat_ready) return "ERROR: First answer not ready";
    if (!question || !*question) return "ERROR: Empty question";
    if (max_tokens < 1 || max_tokens > 2048) return "ERROR: Invalid token limit";
    cancelled = false;
    auto ids = tokenize(next_prompt(question));
    if (chat_pos + static_cast<int>(ids.size()) + max_tokens + 1 >= context_limit) {
        return "ERROR: Context full. Start a new problem.";
    }
    Batch batch(llama_batch_ext_init(ctx), &llama_batch_ext_free);
    if (!batch) return "ERROR: Follow-up batch initialization failed";
    for (size_t start = 0; start < ids.size(); start += 512) {
        if (cancelled.load()) return "CANCELLED";
        const int count = static_cast<int>(std::min<size_t>(512, ids.size() - start));
        llama_batch_ext_clear(batch.get());
        for (int i=0; i<count; ++i) {
            int idx = llama_batch_ext_add_token(batch.get(), 0, ids[start+i]);
            llama_pos pos = chat_pos + static_cast<llama_pos>(start) + i;
            const bool output = start + i + 1 == ids.size();
            if (idx < 0 || !llama_batch_ext_set_pos(batch.get(), idx, &pos) ||
                !llama_batch_ext_set_output_logits(batch.get(), idx, output)) {
                return "ERROR: Follow-up batch construction failed";
            }
        }
        if (llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch.get()) != 0) {
            return "ERROR: Follow-up prefill failed";
        }
    }
    chat_pos += static_cast<llama_pos>(ids.size());
    return decode_tokens(chat_pos, max_tokens, callback, user_data);
}
} // namespace

extern "C" const char *mate_load(const char *llm_file, const char *mmproj_file,
                                 int32_t nctx, int32_t nthreads, int32_t nthreads_batch) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!file_exists(llm_file) || !file_exists(mmproj_file)) return failed("GGUF file missing");
    if (model && ctx && vision && model_path == llm_file && vision_path == mmproj_file) {
        return success("OK: reused loaded model");
    }
    unload_locked();
    cancelled = false;
    try {
        std::call_once(backend_once, [] { llama_backend_init(); });
        llama_model_params mp = llama_model_default_params();
        // Begin conservatively. On Apple Silicon, benchmark Metal layers only after memory checks.
        mp.n_gpu_layers = 0;
        mp.load_mode = LLAMA_LOAD_MODE_MMAP;
        mp.use_extra_bufts = false;
        model = llama_model_load_from_file(llm_file, mp);
        if (!model) { unload_locked(); return failed("LLM load failed"); }
        llama_context_params cp = llama_context_default_params();
        cp.n_ctx = static_cast<uint32_t>(std::clamp<int>(nctx, 512, 2048));
        cp.n_batch = 512;
        cp.n_ubatch = 256;
        cp.n_threads = std::clamp<int>(nthreads, 1, 8);
        cp.n_threads_batch = std::clamp<int>(nthreads_batch, 1, 8);
        cp.n_seq_max = 1;
        cp.type_k = GGML_TYPE_Q8_0;
        cp.type_v = GGML_TYPE_Q4_0;
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        cp.offload_kqv = false;
        cp.op_offload = false;
        ctx = llama_init_from_model(model, cp);
        if (!ctx) { unload_locked(); return failed("Context load failed"); }
        context_limit = static_cast<int>(llama_n_ctx(ctx));
        mtmd_context_params vp = mtmd_context_params_default();
        vp.use_gpu = true; // Metal vision encoder
        vp.n_threads = std::clamp<int>(nthreads_batch, 1, 8);
        vp.warmup = false;
        vp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        vp.image_min_tokens = 96;
        vp.image_max_tokens = 128;
        vp.batch_max_tokens = 256;
        vision = mtmd_init_from_file(mmproj_file, model, vp);
        if (!vision || !mtmd_support_vision(vision)) {
            unload_locked(); return failed("mmproj load failed/incompatible");
        }
        model_path = llm_file; vision_path = mmproj_file;
        return success("OK: loaded same GGUF files; Metal vision enabled");
    } catch (const std::exception &ex) {
        unload_locked();
        return success(std::string("ERROR: ") + ex.what());
    } catch (...) {
        unload_locked(); return failed("Unknown native exception");
    }
}

extern "C" const char *mate_generate_image(const char *image, const char *question,
                                             int32_t max_tokens, mate_token_callback cb, void *user) {
    std::lock_guard<std::mutex> lock(mutex_);
    try { return success(first_locked(image, question, max_tokens, cb, user)); }
    catch (const std::exception &e) { chat_ready = false; return success(std::string("ERROR: ") + e.what()); }
}
extern "C" const char *mate_followup(const char *question, int32_t max_tokens,
                                     mate_token_callback cb, void *user) {
    std::lock_guard<std::mutex> lock(mutex_);
    try { return success(follow_locked(question, max_tokens, cb, user)); }
    catch (const std::exception &e) { chat_ready = false; return success(std::string("ERROR: ") + e.what()); }
}
extern "C" void mate_cancel(void) { cancelled = true; }
extern "C" void mate_unload(void) { std::lock_guard<std::mutex> lock(mutex_); unload_locked(); }

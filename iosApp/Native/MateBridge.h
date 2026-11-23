#ifndef MATE_BRIDGE_H
#define MATE_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Return values point to thread-local storage; copy immediately in Swift.
typedef void (*mate_token_callback)(const char *utf8_piece, void *user_data);
const char *mate_load(const char *model_file, const char *vision_file,
                      int32_t context_length, int32_t generation_threads, int32_t prefill_threads);
const char *mate_generate_image(const char *image_file, const char *question,
                                int32_t max_tokens, mate_token_callback callback, void *user_data);
const char *mate_followup(const char *question, int32_t max_tokens,
                          mate_token_callback callback, void *user_data);
void mate_cancel(void);
void mate_unload(void);
#ifdef __cplusplus
}
#endif
#endif

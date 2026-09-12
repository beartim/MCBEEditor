#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
  #ifdef MCBE_LEVELDB_NATIVE_EXPORTS
    #define MCBE_API __declspec(dllexport)
  #else
    #define MCBE_API __declspec(dllimport)
  #endif
#else
  #define MCBE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* mcbe_db_t;
typedef void* mcbe_iter_t;
typedef void* mcbe_batch_t;

MCBE_API int mcbe_db_open(const char* path_utf8, int read_only, mcbe_db_t* out_db, char** out_error);
MCBE_API void mcbe_db_close(mcbe_db_t db);

/* get: 1 = found, 0 = not found, -1 = error. Returned value uses mcbe_free. */
MCBE_API int mcbe_db_get(mcbe_db_t db, const uint8_t* key, size_t key_len,
                         uint8_t** out_value, size_t* out_value_len, char** out_error);
MCBE_API int mcbe_db_put(mcbe_db_t db, const uint8_t* key, size_t key_len,
                         const uint8_t* value, size_t value_len, int sync, char** out_error);
MCBE_API int mcbe_db_delete(mcbe_db_t db, const uint8_t* key, size_t key_len,
                            int sync, char** out_error);

MCBE_API mcbe_batch_t mcbe_batch_create(void);
MCBE_API void mcbe_batch_destroy(mcbe_batch_t batch);
MCBE_API int mcbe_batch_put(mcbe_batch_t batch, const uint8_t* key, size_t key_len,
                            const uint8_t* value, size_t value_len, char** out_error);
MCBE_API int mcbe_batch_delete(mcbe_batch_t batch, const uint8_t* key, size_t key_len, char** out_error);
MCBE_API int mcbe_db_write_batch(mcbe_db_t db, mcbe_batch_t batch, int sync, char** out_error);

MCBE_API mcbe_iter_t mcbe_iter_create(mcbe_db_t db, const uint8_t* prefix, size_t prefix_len,
                                      int include_values, char** out_error);
MCBE_API void mcbe_iter_destroy(mcbe_iter_t iterator);
MCBE_API int mcbe_iter_valid(mcbe_iter_t iterator);
MCBE_API void mcbe_iter_next(mcbe_iter_t iterator);
/* Pointers returned below are owned by LevelDB and stay valid until the iterator moves/dies. */
MCBE_API const uint8_t* mcbe_iter_key(mcbe_iter_t iterator, size_t* out_len);
MCBE_API const uint8_t* mcbe_iter_value(mcbe_iter_t iterator, size_t* out_len);
MCBE_API int mcbe_iter_status(mcbe_iter_t iterator, char** out_error);

MCBE_API void mcbe_free(void* pointer);

#ifdef __cplusplus
}
#endif

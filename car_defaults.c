#include <stdlib.h>

void*	car_default_realloc(void* ptr, size_t size, void* userdata) {
	if (ptr) {
		if (size) {
			return realloc(ptr, size);
		} else {
			free(ptr);
			return NULL;
		}
	} else {
		if (size) {
			return malloc(size);
		} else {
			return NULL;
		}
	}
}

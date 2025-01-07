// Cardinal Language
//
// (C) 2024 Thomas Doylend.
//
// This software is distributed under the terms of the MIT License. Please see the LICENSE file
// for details.

#include <string.h>
#include <stdint.h>

#include <stdio.h>

#define MAX_CLASS_NAME		64

typedef		struct CarVM			CarVM;
typedef		struct CarObj			CarObj;
typedef		struct CarModule		CarModule;
typedef		struct CarString		CarString;
typedef		struct CarClass			CarClass;
typedef		struct CarConfig		CarConfig;

typedef		struct CarValue			CarValue;

typedef		struct CarValueBuffer	CarValueBuffer;
typedef		struct CarSymbolTable	CarSymbolTable;

#define RC_MAX 0xFFFFFFFF
typedef		uint32_t				rc_t;
typedef		uint64_t				hash_t;

hash_t		car_hash_bytes(const uint8_t* bytes, size_t count);

hash_t		car_hash_bytes(const uint8_t* bytes, size_t count) {
	// TODO
	hash_t result = 0x00;
	for (size_t i = 0; i < count; i ++) {
		result ^= bytes[i];
	}
	return result;
}

enum CarGcColor {
	CAR_GOLD,
	CAR_SILVER,
	CAR_RED,
	CAR_BLUE
};

enum CarObjType {
	CAR_CLASS,
	CAR_STRING,
	CAR_MODULE,
	CAR_CODE
};
typedef		enum CarObjType			CarObjType;
typedef		enum CarGcColor			CarGcColor;

struct CarValue {
	uint64_t	bits;
};

struct CarSymbolTable {
	char**		symbols;
	size_t		count;
	size_t		capacity;
};

void		car_init_symbol_table(CarVM* vm, CarSymbolTable* table);
void		car_finish_symbol_table(CarVM* vm, CarSymbolTable* table);
ptrdiff_t	car_get_symbol(CarVM* vm, CarSymbolTable* table);
ptrdiff_t	car_get_or_add_symbol(CarVM* vm, CarSymbolTable* table);

struct CarValueBuffer {
	CarValue*	values;
	size_t		count;
	size_t		capacity;
};

void		car_init_value_buffer(CarVM* vm, CarValueBuffer* buf);
void		car_finish_value_buffer(CarVM* vm, CarValueBuffer* buf);
void		car_push_value(CarVM* vm, CarValueBuffer* buf, CarValue value);
CarValue	car_pop_value(CarVM* vm, CarValueBuffer* buf);
void	car_inc_rc(CarVM* vm, CarObj* obj);

struct CarObj {
	rc_t		refcount;
	CarGcColor	color;
	CarObjType	obj_type;
	CarClass*	class;
	CarObj*		next;
	CarObj**	prev_next;
};

struct CarVM {
	void* (*realloc_fn)(void* ptr, size_t size, void* userdata);
	void* userdata;

	CarClass*	string_class;
	CarClass*	obj_class;
	CarClass*	class_class;
	
	CarClass*	bool_class;
	CarClass*	fn_class;
	CarClass*	list_class;
	CarClass*	map_class;
	CarClass*	null_class;
	CarClass*	num_class;
	CarClass*	range_class;
	CarClass*	sequence_class;
	CarClass*	system_class;

	CarObj*		red_pool;
	CarObj*		blue_pool;
	CarObj*		gold_pool;
	CarObj*		silver_pool;

	CarGcColor	active_color;
};

CarVM*		car_new_vm(CarConfig* config);
void		car_free_vm(CarVM* vm);
void*		car_vm_alloc(CarVM* vm, size_t size);
void		car_vm_free(CarVM* vm, void* ptr);
void*		car_vm_realloc(CarVM* vm, void* ptr, size_t size);
CarObj* car_setup_obj_without_class(CarVM* vm, CarObjType obj_type, size_t size) {
	CarObj* obj = car_vm_alloc(vm, size);
	obj->refcount = 1;
	obj->color = CAR_GOLD;
	obj->obj_type = obj_type;
	obj->class = NULL;
	obj->next = vm->gold_pool;
	obj->prev_next = &vm->gold_pool;
	vm->gold_pool = obj;
	if (obj->next) obj->next->prev_next = &obj->next;
	return obj;
}

CarObj* car_setup_obj(CarVM* vm, CarObjType obj_type, size_t size, CarClass* class) {
	CarObj* obj = car_setup_obj_without_class(vm, obj_type, size);
	obj->class = class;
	//car_inc_rc(vm, (CarObj*)(obj->class));
	return obj;
}
void	car_rebind_obj_class(CarVM* vm, CarObj* obj, CarClass* new_class);
void	car_recolor_obj(CarVM* vm, CarObj* obj, CarGcColor new_color);
void	car_process_silver(CarVM* vm, CarObj* obj);
void	car_free_obj(CarVM* vm, CarObj* obj);
void	car_inc_rc(CarVM* vm, CarObj* obj);
void	car_dec_rc(CarVM* vm, CarObj* obj);

struct CarString {
	CarObj		obj;
	size_t		byte_count;
	hash_t		hash;
	uint8_t		bytes[];
};

CarString*	car_new_string(CarVM* vm, uint8_t* bytes, size_t count);
CarString*	car_new_string_from_cstring(CarVM* vm, const char* string);

struct CarClass {
	CarObj			obj;
	CarString*		name;
	CarClass*		superclass;
	int				num_fields;
	// CarMethodBuffer	methods;
};

CarString* car_new_string(CarVM* vm, uint8_t* bytes, size_t count) {
	CarString* string = (CarString*)car_setup_obj(
			vm,
			CAR_STRING,
			sizeof(CarString) + count + 1,
			vm->string_class
	);
	memcpy(string->bytes, bytes, count);
	string->bytes[count] = 0;
	string->byte_count = count;
	string->hash = car_hash_bytes(string->bytes, string->byte_count);
	return string;
}

CarString*	car_new_string_from_cstring(CarVM* vm, const char* string) {
	return car_new_string(vm, (uint8_t*)string, strlen(string));

}

CarClass*	car_new_class(CarVM* vm, const char* name, CarClass* superclass);
void		car_bind_superclass(CarVM* vm, CarClass* class, CarClass* superclass);
//void		car_bind_method(CarVM* vm, size_t index, CarProcedure* method);

void*		car_default_realloc(void* ptr, size_t size, void* userdata);

struct CarModule {
	CarObj			obj;
	CarSymbolTable	global_names;
	CarValueBuffer	globals;
};

CarModule*	car_new_module(CarVM* vm, const char* name);
size_t		car_get_global(CarVM* vm, CarModule* module, const char* global);
size_t		car_get_or_create_global(CarVM* vm, CarModule* module, const char* global);

struct CarConfig {
	void* (*realloc_fn)(void* ptr, size_t size, void* userdata);

	void* userdata;
};

void		car_init_config_bare(CarConfig* config) {
	config->realloc_fn = NULL;
}

void		car_init_config(CarConfig* config) {
	config->realloc_fn = &car_default_realloc;
}

CarClass* car_new_class(CarVM* vm, const char* name, CarClass* superclass) {
	char metaclass_name[MAX_CLASS_NAME + 11];
	strncpy(metaclass_name, name, MAX_CLASS_NAME);
	metaclass_name[MAX_CLASS_NAME] = 0;
	strcat(metaclass_name, " metaclass");

	CarString* name_obj = car_new_string_from_cstring(vm, name);
	CarString* meta_name_obj = car_new_string_from_cstring(vm, metaclass_name);

	CarClass* metaclass = (CarClass*)car_setup_obj(vm, CAR_CLASS, sizeof(CarClass),
			vm->class_class);
	CarClass* class = (CarClass*)car_setup_obj(vm, CAR_CLASS, sizeof(CarClass), metaclass);

	metaclass->name = meta_name_obj;
	metaclass->superclass = vm->class_class;
	metaclass->num_fields = 0;

	class->name = name_obj;
	class->superclass = superclass;
	class->num_fields = 0;

	car_recolor_obj(vm, &metaclass->obj, vm->active_color);
	car_recolor_obj(vm, &meta_name_obj->obj, vm->active_color);
	car_recolor_obj(vm, &name_obj->obj, vm->active_color);

	return class;
}

void car_recolor_obj(CarVM* vm, CarObj* obj, CarGcColor new_color) {
	if (new_color == obj->color) return;

	CarObj** new_pool;

	switch (new_color) {
		CAR_RED: new_pool = &vm->red_pool; break;
		CAR_BLUE: new_pool = &vm->blue_pool; break;
		CAR_SILVER: new_pool = &vm->silver_pool; break;
		CAR_GOLD: new_pool = &vm->gold_pool; break;
	}

	if (obj->next) {
		*obj->prev_next = &obj->next;
		obj->next->prev_next = obj->prev_next;
	} else {
		*obj->prev_next = NULL;
	}

	if (*new_pool) {
		new_pool->prev_next = &obj->next;
	}
	obj->next = new_pool;
	*new_pool = obj;
	obj->prev_next = &new_pool;
}

CarVM*		car_new_vm(CarConfig* config) {
	CarVM* vm = config->realloc_fn(NULL, sizeof(CarVM), config->userdata);
	vm->userdata = config->userdata;
	vm->realloc_fn = config->realloc_fn;

	vm->red_pool = NULL;
	vm->blue_pool = NULL;
	vm->gold_pool = NULL;
	vm->silver_pool = NULL;

	// TODO turn off GC while doing this!
	CarClass* obj_class			= (CarClass*)car_setup_obj_without_class(vm, CAR_CLASS,
			sizeof(CarClass));
	CarClass* obj_metaclass		= (CarClass*)car_setup_obj_without_class(vm, CAR_CLASS,
			sizeof(CarClass));
	CarClass* class_class		= (CarClass*)car_setup_obj_without_class(vm, CAR_CLASS,
			sizeof(CarClass));
	CarClass* string_class		= (CarClass*)car_setup_obj_without_class(vm, CAR_CLASS,
			sizeof(CarClass));
	CarClass* string_metaclass	= (CarClass*)car_setup_obj_without_class(vm, CAR_CLASS,
			sizeof(CarClass));

	obj_class->obj.class		= obj_metaclass;
	obj_metaclass->obj.class	= class_class;
	class_class->obj.class		= class_class;
	string_class->obj.class		= string_metaclass;
	string_metaclass->obj.class	= class_class;

	obj_class->superclass		= NULL;
	obj_metaclass->superclass	= class_class;
	class_class->superclass		= obj_class;
	string_class->superclass	= obj_class;
	string_metaclass->superclass= class_class;

	vm->class_class = class_class;
	vm->obj_class = obj_class;
	vm->string_class = string_class;

	for (int i=0; i < 2; i++) car_inc_rc(vm, (CarObj*)obj_class);
	for (int i=0; i < 1; i++) car_inc_rc(vm, (CarObj*)obj_metaclass);
	for (int i=0; i < 5; i++) car_inc_rc(vm, (CarObj*)class_class);
	for (int i=0; i < 0; i++) car_inc_rc(vm, (CarObj*)string_class);
	for (int i=0; i < 1; i++) car_inc_rc(vm, (CarObj*)string_metaclass);

	obj_class->name = car_new_string_from_cstring(vm, "Obj");
	obj_metaclass->name = car_new_string_from_cstring(vm, "Obj metaclass");
	class_class->name = car_new_string_from_cstring(vm, "Class");
	string_class->name = car_new_string_from_cstring(vm, "String");
	string_metaclass->name = car_new_string_from_cstring(vm, "String metaclass");

	vm->sequence_class = car_new_class(vm, "Sequence", vm->obj_class);
	vm->bool_class	= car_new_class(vm, "Bool", vm->obj_class);
	vm->fn_class	= car_new_class(vm, "Fn", vm->obj_class);
	vm->list_class	= car_new_class(vm, "List", vm->sequence_class);
	vm->map_class	= car_new_class(vm, "Map", vm->sequence_class);
	vm->null_class	= car_new_class(vm, "Null", vm->obj_class);
	vm->num_class	= car_new_class(vm, "Num", vm->obj_class);
	vm->range_class	= car_new_class(vm, "Range", vm->sequence_class);
	vm->system_class = car_new_class(vm, "System", vm->obj_class);
	
	return vm;
}

void car_inc_rc(CarVM* vm, CarObj* obj) {
	if (obj->refcount < RC_MAX) obj->refcount ++;
}

void car_free_vm(CarVM* vm) {
	void* userdata = vm->userdata;
	void* (*realloc_fn)(void* ptr, size_t size, void* userdata) = vm->realloc_fn;
	// TODO
	realloc_fn(vm, 0, userdata);
}

void* car_vm_alloc(CarVM* vm, size_t size) {
	return vm->realloc_fn(NULL, size, vm->userdata);
}



void car_init_symbol_table(CarVM* vm, CarSymbolTable* table) {
	table->symbols = NULL;
	table->count = 0;
	table->capacity = 0;
}

void car_finish_symbol_table(CarVM* vm, CarSymbolTable* table) {
	while (table->count) {
		table->count --;
		car_vm_free(vm, table->symbols[table->count]);
	}
	if (table->symbols) car_vm_free(vm, table->symbols);
	table->capacity = 0;
}

void car_vm_free(CarVM* vm, void* ptr) {
	vm->realloc_fn(ptr, 0, vm->userdata);
}

#include <stdio.h>
int main(void) {
	printf("[Program Start]\n");
	
	CarConfig config;
	car_init_config(&config);

	CarVM* vm = car_new_vm(&config);

	car_free_vm(vm);

	printf("[Program End]\n");

	return 0;
}

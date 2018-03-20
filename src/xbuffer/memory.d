module xbuffer.memory;

import core.exception : onOutOfMemoryError;
import core.stdc.stdlib : _malloc = malloc, _calloc = calloc, _realloc = realloc, _free = free;

import std.conv : emplace;

void[] malloc(size_t size) nothrow @nogc {
	void* ptr = _malloc(size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..size];
}

void[] calloc(size_t size) nothrow @nogc {
	void* ptr = _calloc(1, size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..size];
}

void[] realloc(void* ptr, size_t size) nothrow @nogc {
	void* new_ptr = _realloc(ptr, size);
	if(new_ptr is null) onOutOfMemoryError();
	return new_ptr[0..size];
}

void free(void* ptr) nothrow @nogc {
	_free(ptr);
}

T alloc(T, E...)(auto ref E args) @nogc if(is(T == class)) {
	return emplace!(T, E)(calloc(__traits(classInstanceSize, T)), args);
}

void free(T)(T obj) nothrow @nogc if(is(T == class)) {
	static if(__traits(hasMember, T, "__xdtor")) obj.__xdtor();
	free(cast(void*)obj);
}

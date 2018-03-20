module xbuffer.memory;

import core.exception : onOutOfMemoryError;
import core.memory : pureMalloc, pureCalloc, pureRealloc, pureFree;

import std.conv : emplace;

void[] malloc(size_t size) pure nothrow @trusted @nogc {
	void* ptr = pureMalloc(size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..size];
}

void[] calloc(size_t size) pure nothrow @trusted @nogc {
	void* ptr = pureCalloc(1, size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..size];
}

void[] realloc(void* ptr, size_t size) pure nothrow @trusted @nogc {
	void* new_ptr = pureRealloc(ptr, size);
	if(new_ptr is null) onOutOfMemoryError();
	return new_ptr[0..size];
}

void free(void* ptr) pure nothrow @system @nogc {
	pureFree(ptr);
}

T alloc(T, E...)(auto ref E args) @nogc if(is(T == class)) {
	return emplace!(T, E)(calloc(__traits(classInstanceSize, T)), args);
}

void free(T)(T obj) pure nothrow @system @nogc if(is(T == class)) {
	static if(__traits(hasMember, T, "__xdtor")) obj.__xdtor();
	free(cast(void*)obj);
}

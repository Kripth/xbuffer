module xbuffer.memory;

import core.exception : onOutOfMemoryError;
import core.memory : pureMalloc, pureCalloc, pureRealloc, pureFree;

import std.conv : emplace;

/**
 * Uses `pureMalloc` to allocate a block of memory of the given
 * size and throws an `outOfMemoryError` if the memory cannot be
 * allocated.
 */
void[] xmalloc(size_t size) pure nothrow @trusted @nogc {
	void* ptr = pureMalloc(size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..size];
}

///
pure nothrow @trusted @nogc unittest {

	ubyte[] bytes = cast(ubyte[])xmalloc(12);
	assert(bytes.length == 12);

	int[] ints = cast(int[])xmalloc(12);
	assert(ints.length == 3);

}

/**
 * Uses `pureCalloc` to allocate a block of memory of the given
 * size and trows an `outOfMemoryError` if the memory cannot be
 * allocated.
 */
void[] xcalloc(size_t nitems, size_t size) pure nothrow @trusted @nogc {
	void* ptr = pureCalloc(nitems, size);
	if(ptr is null) onOutOfMemoryError();
	return ptr[0..nitems*size];
}

///
pure nothrow @trusted @nogc unittest {

	ubyte[] bytes = cast(ubyte[])xcalloc(12, 1);
	assert(bytes.length == 12);

	int[] ints = cast(int[])xcalloc(3, 4);
	assert(ints.length == 3);

}

/**
 * Uses `pureRealloc` to realloc a block of memory and throws an
 * `outOfMemoryError` if the memory cannot be allocated.
 */
void[] xrealloc(void* ptr, size_t size) pure nothrow @trusted @nogc {
	void* new_ptr = pureRealloc(ptr, size);
	if(new_ptr is null) onOutOfMemoryError();
	return new_ptr[0..size];
}

///
pure nothrow @trusted @nogc unittest {

	void[] buffer = xmalloc(12);
	assert(buffer.length == 12);

	// allocate
	buffer = xrealloc(buffer.ptr, 100);
	assert(buffer.length == 100);

	// deallocate
	buffer = xrealloc(buffer, 10);
	assert(buffer.length == 10);

}

/**
 * Reallocates the given array using a new size.
 */
void[] xrealloc(T)(ref T[] buffer, size_t size) pure nothrow @trusted @nogc {
	return (buffer = cast(T[])xrealloc(buffer.ptr, size * T.sizeof));
}

///
pure nothrow @trusted @nogc unittest {

	ubyte[] bytes = cast(ubyte[])xmalloc(12);
	xrealloc(bytes, 44); // same as `xrealloc(bytes.ptr, 44)`
	assert(bytes.length == 44);

	int[] ints = cast(int[])xcalloc(3, 4);
	assert(ints.length == 3);
	xrealloc(ints, 4); // same as `xrealloc(ints.ptr, 4 * 4)`
	assert(ints.length == 4);

}

/**
 * Uses `pureFree` to release allocated memory.
 */
void xfree(void* ptr) pure nothrow @system @nogc {
	pureFree(ptr);
}

/// ditto
void xfree(T)(ref T[] array) pure nothrow @nogc {
	xfree(array.ptr);
}

/**
 * Allocates memory for a class and emplaces it.
 */
T xalloc(T, E...)(auto ref E args) pure nothrow @system @nogc if(is(T == class)) {
	return emplace!(T, E)(xmalloc(__traits(classInstanceSize, T)), args);
}

///
pure nothrow @trusted @nogc unittest {

	class Test {

		int a, b, c;

	}

	Test test;
	assert(test is null);

	test = xalloc!Test();
	assert(test !is null);

}

/**
 * Deallocates a class allocated with xalloc and calls its custom
 * destructor (`__xdtor` pure, nothrow and @nogc method).
 */
void xfree(T)(T obj) pure nothrow @system @nogc if(is(T == class)) {
	static if(__traits(hasMember, T, "__xdtor")) obj.__xdtor();
	else obj.__dtor();
	xfree(cast(void*)obj);
}

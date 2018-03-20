module xbuffer.varint;

import std.traits : isIntegral, isSigned, isUnsigned, Unsigned;

import xbuffer.buffer : Buffer;

enum isVar(T) = is(T == Var!V, V);

// debug
import std.stdio : writeln;

unittest {
	
	static assert(isVar!varshort);
	static assert(!isVar!short);
	
}

struct Var(T) if(isIntegral!T && T.sizeof > 1) {
	
	alias Base = T;
	
	static if(isSigned!T) alias U = Unsigned!T;
	
	@disable this();
	
	static void encode(Buffer buffer, T value) nothrow @safe @nogc {
		static if(isUnsigned!T) {
			while(value > 0x7F) {
				buffer.write!ubyte((value & 0x7F) | 0x80);
				value >>>= 7;
			}
			buffer.write!ubyte(value & 0x7F);
		} else {
			static if(T.sizeof < int.sizeof) Var!U.encode(buffer, cast(U)(value >= 0 ? value << 1 : (-cast(int)value << 1) - 1));
			else Var!U.encode(buffer, value >= 0 ? value << 1 : (-value << 1) - 1);
		}
	}

	//FIXME add ad limit to the number of bytes readed (3, 5, 10)
	static T decode(Buffer buffer) @safe @nogc {
		static if(isUnsigned!T) {
			T ret;
			ubyte next;
			size_t shift;
			do {
				next = buffer.read!ubyte();
				ret |= T(next & 0x7F) << shift;
				shift += 7;
			} while(next > 0x7F);
			return ret;
		} else {
			U ret = Var!U.decode(buffer);
			if(ret & 1) return ((ret >> 1) + 1) * -1;
			else return ret >> 1;
		}
	}
	
}

alias varshort = Var!short;

alias varushort = Var!ushort;

alias varint = Var!int;

alias varuint = Var!uint;

alias varlong = Var!long;

alias varulong = Var!ulong;

unittest {
	
	Buffer buffer = new Buffer(16);
	
	varint.encode(buffer, 0);
	assert(buffer.data!ubyte == [0]);
	
	buffer.reset();
	varint.encode(buffer, -1);
	varint.encode(buffer, 1);
	varint.encode(buffer, -2);
	assert(buffer.data!ubyte == [1, 2, 3]);
	
	buffer.reset();
	varint.encode(buffer, 2147483647);
	varint.encode(buffer, -2147483648);
	assert(buffer.data!ubyte == [254, 255, 255, 255, 15, 255, 255, 255, 255, 15]);
	
	assert(varint.decode(buffer) == 2147483647);
	assert(varint.decode(buffer) == -2147483648);
	
	buffer.data = cast(ubyte[])[1, 2, 3];
	assert(varint.decode(buffer) == -1);
	assert(varint.decode(buffer) == 1);
	assert(varint.decode(buffer) == -2);
	
	varuint.encode(buffer, 1);
	varuint.encode(buffer, 2);
	varuint.encode(buffer, uint.max);
	assert(buffer.data!ubyte == [1, 2, 255, 255, 255, 255, 15]); 
	assert(varushort.decode(buffer) == 1);
	assert(varuint.decode(buffer) == 2);
	assert(varulong.decode(buffer) == uint.max);
	
}

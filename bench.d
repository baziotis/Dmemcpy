import std.datetime.stopwatch;
import Dmemcpy: Dmemcpy, Cmemcpy;
import S_struct;
import std.random;
import std.stdio;
import core.stdc.string;
import std.traits;

///
///   A big thanks to Mike Franklin (JinShil). A big part of code is taken from his memcpyD implementation.
///

// From a very good Chandler Carruth video on benchmarking: https://www.youtube.com/watch?v=nXaxk27zwlk
void escape(void* p)
{
    version(LDC)
    {
        import ldc.llvmasm;
         __asm("", "r,~{memory}", p);
    }
    version(GNU)
    {
        asm { "" : : "g" p : "memory"; }
    }
}

void clobber()
{
    version(LDC)
    {
        import ldc.llvmasm;
        __asm("", "~{memory}");
    }
    version(GNU)
    {
        asm { "" : : : "memory"; }
    }
}

Duration benchmark(T, alias f)(T *dst, T *src, ulong* bytesCopied)
{
    enum iterations = 2^^20 / T.sizeof;
    Duration result;

    auto swt = StopWatch(AutoStart.yes);
    swt.reset();
    while(swt.peek().total!"msecs" < 50)
    {
        auto sw = StopWatch(AutoStart.yes);
        sw.reset();
        foreach (_; 0 .. iterations)
        {
            escape(&dst);   // So optimizer doesn't remove code
            f(dst, src);
            escape(&src);   // So optimizer doesn't remove code
        }
        result += sw.peek();
        *bytesCopied += (iterations * T.sizeof);
    }

    return result;
}

void init(T)(T *v)
{
    static if (is (T == float))
    {
        v = uniform(0.0f, 9_999_999.0f);
    }
    else static if (is(T == double))
    {
        v = uniform(0.0, 9_999_999.0);
    }
    else static if (is(T == real))
    {
        v = uniform(0.0L, 9_999_999.0L);
    }
    else
    {
        auto m = (cast(ubyte*)v)[0 .. T.sizeof];
        for(int i = 0; i < m.length; i++)
        {
            m[i] = uniform!byte;
        }
    }
}

void verify(T)(const T *a, const T *b)
{
    auto aa = (cast(ubyte*)a)[0..T.sizeof];
    auto bb = (cast(ubyte*)b)[0..T.sizeof];
    for(int i = 0; i < T.sizeof; i++)
    {
        assert(aa[i] == bb[i]);
    }
}

bool average;

void test(T)()
{
    ubyte[80000] buf1;
    ubyte[80000] buf2;

    double TotalGBperSec1 = 0.0;
    double TotalGBperSec2 = 0.0;
    enum alignments = 32;

    foreach(i; 0..alignments)
    {
        {
            T* d = cast(T*)(&buf1[i]);
            T* s = cast(T*)(&buf2[i]);

            ulong bytesCopied1;
            ulong bytesCopied2;
            init(d);
            init(s);
            immutable d1 = benchmark!(T, Cmemcpy)(d, s, &bytesCopied1);
            verify(d, s);

            init(d);
            init(s);
            immutable d2 = benchmark!(T, Dmemcpy)(d, s, &bytesCopied2);
            verify(d, s);

            auto secs1 = (cast(double)(d1.total!"nsecs")) / 1_000_000_000.0;
            auto secs2 = (cast(double)(d2.total!"nsecs")) / 1_000_000_000.0;
            auto GB1 = (cast(double)bytesCopied1) / 1_000_000_000.0;
            auto GB2 = (cast(double)bytesCopied2) / 1_000_000_000.0;
            auto GBperSec1 = GB1 / secs1;
            auto GBperSec2 = GB2 / secs2;
            if (average)
            {
                TotalGBperSec1 += GBperSec1;
                TotalGBperSec2 += GBperSec2;
            }
            else
            {
                writeln(T.sizeof, " ", GBperSec1, " ", GBperSec2);
                stdout.flush();
            }
        }
    }

    if (average)
    {
        writeln(T.sizeof, " ", TotalGBperSec1 / alignments, " ", TotalGBperSec2 / alignments);
        stdout.flush();
    }
}

enum Aligned = true;
enum MisAligned = false;

void main(string[] args)
{
    average = args.length >= 2;

    // For performing benchmarks
    writeln("size(bytes) Cmemcpy(GB/s) Dmemcpy(GB/s)");
    stdout.flush();
    static foreach(i; 120..130)
    {
        test!(S!i);
    }
    static foreach(i; 220..230)
    {
        test!(S!i);
    }
    static foreach(i; 720..730)
    {
        test!(S!i);
    }   
    test!(S!3452);
    test!(S!6598);
    test!(S!14928);
    test!(S!27891);
    test!(S!44032);
    test!(S!55897);
    test!(S!79394);
}
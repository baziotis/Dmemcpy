# Dmemcpy

This is part of my [Google Summer of Code project](https://summerofcode.withgoogle.com/organizations/6103365956665344/#5475582328963072), _Independency of D from the C Standard Library_.

It is a public repository for the work on the `memcpy()` replacement.

You can read more info about this project in this [Dlang forum thread](https://forum.dlang.org/thread/izaufklyvmktnwsrmhci@forum.dlang.org).

## NOTES

The following notes are based on the assumption that we <b>compile with DMD</b>.

### ASM performance
For some reason, if you take asm directly from GCC and translate it to D,
it will be (quite) slower. I don't specifically know why this happens (one reason
probably is the note below). But certainly, if you are to measure what _actual_ performance
you get from the assembly code that I wrote, you'd have to put it in an assembler
and link the object file.

### Function Prologue and Epilog in ASM functions
A big bottle-neck on small sizes seem to be the function prologues and epilog. 
When using inline asm, DMD for some reason preserves and restores a bunch of registers
that are not actually used. We could potentiall get away from this by setting
the static on our own. Check TODO 1) below.


### Using regular D along with ASM
Ideally, we would like most of the code to not be big asm blocks but instead either be regular D or at least ASM
interleaved with regular D. Unfortunately, early on when I was implementing `Dmemcpy`, it became obvious that this can't
happen. At least I didn't find a way to do it. <br/>
First of all, a regular D implementation could not compete in any way with hand-written ASM of `libc memcpy`.
Second, interleaving regular D with ASM decreases performance significantly. The reason is mostly that register allocation
goes badly. In cases where you expect a variable to reside in a register, it gets load from memory resulting in big performance hit.
It gets worse when variables are used in loops.<br/>
However, I made a D implementation of a C memcpy I wrote, which you can find in `Dopt_memcpy.d`. This was written in a rush
and so I did not have much time to explore its capabilities. For the most part it was not very positive.
Check TODO 2)

### False data dependency and backwards copy
Explore the cases of false data dependency. According to Agner Fog:<br/>
> The CPU may falsely assume a partial overlap between the written destination
> and the following read source if source is unaligned and (src-dest) modulo 4096
> is close to 4096".

Source: https://gist.github.com/thoughtpolice/26ea25f69715ffde96efa6364c19cf18#file-memcpy64-asm-L528

I don't know exactly what Agner does in this implementation (you might want to check where it branches though).
But what is common among `memcpy` implementations is that if `dest` >= `src`, then they do the copy backwards (starting
from the end of buffers and moving to the start).

### General optimization info on aligned / unaligned data
A general topic to be discussed is aligned and unaligned data.
First of all, what is a good alignment is not trivial. One could think that if we're using SSE it is 16, AVX 32 etc.<br/>
But, there's more to it. Because what is important is the cache line size, because processors work really
well when they work in multiples of that. Newer processors have a 64-byte cache-line.
In the info below, what I consider aligned is 64-byte aligned.

The bottle-neck seems to be in stores. In recent architectures (Haswell and then I think), there are
2 load ports and 1 store port.

- #### Aligned:
With that setup, we can do 2 64-byte aligned loads in 1 cycle but only 1 64-byte store. For `memcpy`, we will have to live with the bottle-neck
because for every load there is a store. But consider the case of adding two vectors and output to the third. Now,
for every _2_ loads there's a store and we take maximum performance.

- #### Unaligned:
With unaligned data, we can only do one 64-byte load per cycle. The reason of that we have to load _2 cachelines_. For example:<br/>
multiple of 64&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;multiple of 64<br/>
|&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|<br/>
---------------------------------------- ...<br/>
1st cache line&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;2nd cache line

Now, if we are to load on a multiple of 64, we will load one cache-line and be done. And since there are 2 load ports,
we can load 128 bytes per cycle.
But, if we are to load something here:<br/>

multiple of 64&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;multiple of 64<br/>
|&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|<br/>
---------------------------------------- ...<br/>
1st cache line&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;2nd cache line

Then to get those 64 bytes we have to load the 2 adjacent cache-lines. That of course means we can do 2 32-byte loads in
a cycle.

Recently, I read that rep movsb is faster than SSE (at least) on Intel architectures if we are on 64-byte boundary. And that seems to be the reason.
Check TODO 4)



### `src` and `dst` are mis-aligned relative to each other
Another topic is what happens when `src` and `dst` are unaligned by a _different_ amount. Or put it another way,
they are misaligned relative to each other, or `src % alignment` != `dst % alignment`. To tackle this fully,
one needs to read notes 5) and 6). But also, some other proposed technique by Agner is to load an shift until we reach
same alignment on both. That is, imagine the following:<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|<br/>
src: ---------------<br/>
dst: |</br>

They are mis-aligned by 2. Then load from the source say 4 bytes, write 4 to dest, but now advance source only by 2.<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|<br/>
src: ---------------<br/>
dst:&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|<br/>

And now `src` and `dst` are aligned relative to each other. Another thing to consider is that any reasonable allocator (or compiler
for stack data) will give pointer aligned to some power of 2, which makes this easier (meaning, faster). This should
not be a given though (mostly because the user may end up having changed the alignment).

Source: Agner Fog, Subroutine optimization manual: https://www.agner.org/optimize/optimizing_assembly.pdf

## TODOs
### Related to performance
1) Explore `naked`: https://dlang.org/spec/iasm.html#naked to avoid function prologue and epilog.
2) Explore a regular D implementation, `Dopt_memcpy.d`
3) Benchmark what happens when `dst` > `src`.
4) For asm, we only care about > 64 bytes memcpy. Explore `rep movsb` on 64-byte aligned data. In that regard,
we should also explore the "first align to 64-byte boundary, then rep movsb".
5) Explore the method in note 6) for when `dst` and `src` are misaligned relative to each other.

### Related to the interface
6) Add support for dynamic arrays. This requires some trivial assembly to handle <= 64 bytes data, as we can't
use `static if` because of course the size of copy is only known at runtime.
7) Related to the above, provide bounds checking and other useful wrappers. Jonathan Marler proposed
some interesting ideas here: https://forum.dlang.org/thread/qlmiyizrknrirnhdvpbq@forum.dlang.org

## Compile and Run
`dmd bench.d Dmemcpy.d -O -inline && ./bench average` (DMD - Optimized and Inlined)

## Contact / Feedback
An important reason that I published it so early (about 5 days of work) is to get feedback on different machines,
from different people. <br/>
So, if you are interested in helping, it would be beneficial to do one or more of the following:
  - Test in DMD.
  - Test on Windows or Linux.

See above for compilation and run instructions.
Then just send me the results and your CPU model.

### Contact Info

E-mail: sdi1600105@di.uoa.gr

If you are involved in D, you can also ping me on Slack (Stefanos Baziotis), or post in the dlang forum thread above.

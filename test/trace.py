#!/usr/bin/env python3
"""The frame's dispatch, kernel by kernel: emit the C of a program, patch its
Metal driver to run one command buffer a kernel, time each and count the
tasks left in the lanes' rings after it, and build it.

    bend test/bench.bend -o build/bench.c
    python3 test/trace.py build/bench.c        # writes and builds build/bench_trace
    ./build/bench_trace 2>&1 | grep 'grow\\|work\\|pack'

A `!` is one dispatch of four kernels (bendlang/bend#925): grow1 (one group
of 128 lanes forks the root until each lane's ring holds a task), grow128
(each group does the same with its task), work (rings transposed, each lane
runs its task's whole subtree in sequence), pack. The lines say how many
tasks each grow left, over how many rings, the most in one ring, and how
long each kernel took: a slow work with few tasks a ring is a big subtree
on one lane. This reaches into the runtime's text (Bend 2.0.22), so a new
Bend may need the snippets below updated."""
import subprocess, sys

OLD_PASS = '''static void gpu_pass(u32 f) {
  @autoreleasepool {
    id<MTLCommandBuffer> cb = [gpu_que commandBuffer];
    gpu_enc = [cb computeCommandEncoder];
    gpu_run(f);
    [gpu_enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if ([cb error]) {
      err_fail([[[cb error] localizedDescription] UTF8String]);
    }
  }
}'''

NEW_PASS = '''static void gpu_one(u32 pass, u32 groups, const char* tag) {
  struct timespec a, b;
  clock_gettime(CLOCK_MONOTONIC, &a);
  @autoreleasepool {
    id<MTLCommandBuffer> cb = [gpu_que commandBuffer];
    gpu_enc = [cb computeCommandEncoder];
    gpu_kernel(pass, groups);
    [gpu_enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if ([cb error]) {
      err_fail([[[cb error] localizedDescription] UTF8String]);
    }
  }
  clock_gettime(CLOCK_MONOTONIC, &b);
  Corpus H = CORPUS;
  u64 tasks = 0, rings = 0, mx = 0;
  for (u32 r = 0; r < LANES; r += 1) {
    u32 n = *ring_put(H, r) - *ring_get(H, r);
    tasks += n; rings += n > 0; if (n > mx) mx = n;
  }
  fprintf(stderr, "  %s: %ld us, then tasks=%llu rings=%llu max=%llu\\n", tag,
    (b.tv_sec - a.tv_sec) * 1000000L + (b.tv_nsec - a.tv_nsec) / 1000, tasks, rings, mx);
}

static void gpu_pass(u32 f) {
  if (f < CUBE_T) { gpu_one(0, 1, "grow1"); }
  if (f < LANES) { gpu_one(0, CUBE_G, "grow128"); }
  gpu_one(1, CUBE_G, "work");
  gpu_one(2, 1, "pack");
}'''

OLD_RUN = '''    if (root_done(H)) {
      return;
    }
    if (f == 0) {
      err_fail("frontier drained without a result");
    }'''

NEW_RUN = '''    if (root_done(H)) {
      fprintf(stderr, "\\n");
      return;
    }
    if (f == 0) {
      err_fail("frontier drained without a result");
    }
    fprintf(stderr, "dispatch, frontier %u:\\n", f);'''

def main():
    if len(sys.argv) != 2 or not sys.argv[1].endswith('.c'):
        sys.exit(__doc__)
    src = sys.argv[1]
    s = open(src).read()
    for old in (OLD_PASS, OLD_RUN):
        if s.count(old) != 1:
            sys.exit('the runtime\'s text changed: a snippet was not found once in ' + src)
    s = s.replace(OLD_PASS, NEW_PASS).replace(OLD_RUN, NEW_RUN)
    out = src[:-2] + '_trace'
    open(out + '.c', 'w').write(s)
    cc = ['clang', '-DBEND_METAL=1', '-x', 'objective-c', '-fobjc-arc', '-fmodules', '-std=c11', '-O3',
          out + '.c', '-lpthread', '-lm', '-o', out]
    print(' '.join(cc))
    subprocess.run(cc, check=True, stderr=subprocess.DEVNULL)
    subprocess.run([out, '--gpu-build'], check=True)
    print('built', out)

main()

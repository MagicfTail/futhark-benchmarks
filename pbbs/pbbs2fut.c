// Convert input data from the PBBS format to the Futhark binary data
// format.  Accepts data on stdin and produces results on stdout.  May
// not support all PBBS data formats yet, but should be enough for the
// currently implemented benchmarks.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

void header(FILE *out, uint8_t num_dims, const char *type, uint64_t *dims) {
  uint8_t header = 'b';
  uint8_t version = 2;
  fwrite(&header, 1, 1, out);
  fwrite(&version, 1, 1, out);
  fwrite(&num_dims, 1, 1, out);
  fwrite(type, 4, 1, out);
  for (int i = 0; i < num_dims; i++) {
    fwrite(&dims[i], sizeof(uint64_t), 1, out);
  }
}

void conv_float(FILE *in, FILE *out) {
  float f;
  int ret = fscanf(in, "%f", &f);
  assert(ret == 1);
  fwrite(&f, sizeof(float), 1, out);
}

void conv_i32(FILE *in, FILE *out) {
  int32_t x;
  int ret = fscanf(in, "%d", &x);
  assert(ret == 1);
  fwrite(&x, sizeof(int), 1, out);
}

void sequenceInt(FILE *in, FILE *out) {
  int used = 0, capacity = 100;
  int32_t *data = malloc(capacity*sizeof(int32_t));
  while (fscanf(in, "%d", &data[used]) == 1) {
    if (++used == capacity) {
      capacity *= 2;
      data = realloc(data, capacity*sizeof(int32_t));
    }
  }

  uint64_t dims[1] = {used};
  header(out, 1, " i32", dims);
  fwrite(data, sizeof(int32_t), used, out);
}

void pbbs_triangles(FILE *in, FILE *out) {
  // Assuming 3D triangles.
  int n, m;
  int ret = fscanf(in, "%d\n%d\n", &n, &m);
  assert(ret == 2);

  uint64_t dims[2];
  dims[0] = n;
  dims[1] = 3;
  header(out, 2, " f32", dims);
  for (int i = 0; i < n; i++) {
    conv_float(in, out);
    conv_float(in, out);
    conv_float(in, out);
  }

  dims[0] = m;
  header(out, 2, " i32", dims);
  for (int i = 0; i < m; i++) {
    conv_i32(in, out);
    conv_i32(in, out);
    conv_i32(in, out);
  }
}

void pbbs_sequencePoint3d(FILE *in, FILE *out) {
  int used = 0, capacity = 100;
  float *data = malloc(capacity*sizeof(float));
  while (fscanf(in, "%f", &data[used]) == 1) {
    if (++used == capacity) {
      capacity *= 2;
      data = realloc(data, capacity*sizeof(float));
    }
  }

  assert(used % 6 == 0);
  int n = used / 6;
  uint64_t dims[3] = {n, 2, 3};
  header(out, 3, " f32", dims);
  fwrite(data, sizeof(float), used, out);
}

int main(int argc, char** argv) {
  char* line;
  size_t n;

  if (argc != 1) {
    fprintf(stderr, "%s takes no options.\n", argv[0]);
    exit(1);
  }

  if (isatty(fileno(stdin))) {
    fprintf(stderr, "stdin is a tty - you probably want to redirect from a file instead.\n");
  }

  getline(&line, &n, stdin);

  if (strcmp(line, "sequenceInt\n") == 0) {
    sequenceInt(stdin, stdout);
  } else if (strcmp(line, "pbbs_triangles\n") == 0) {
    pbbs_triangles(stdin, stdout);
  } else if (strcmp(line, "pbbs_sequencePoint3d\n") == 0) {
    pbbs_sequencePoint3d(stdin, stdout);
  } else {
    fprintf(stderr, "Unknown file type: %s\n", line);
    exit(1);
  }

  free(line);
}

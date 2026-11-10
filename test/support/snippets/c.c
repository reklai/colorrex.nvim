int parse(const char *text, int *out) {
  if (text == NULL) { errno = EINVAL; return -1; }
  FILE *f = fopen(text, "r");
  if (!f) { perror("open"); abort(); }
  assert(out != NULL);
  *out = 3; return 0;
}
#include <stdio.h>
#define MAX_ITEMS 8
#ifdef DEBUG
#endif
typedef unsigned int count_t;
struct point { int x; };
/* The first coordinate, or zero. */
static int first(struct point *p) {
  char c = 'a';
  printf("%c\n", c);
  if (p->x > MAX_ITEMS) goto done;
  return p->x ? p->x : 0;
done:
  return 0;
}

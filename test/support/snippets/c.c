int parse(const char *text, int *out) {
  if (text == NULL) { errno = EINVAL; return -1; }
  FILE *f = fopen(text, "r");
  if (!f) { perror("open"); abort(); }
  assert(out != NULL);
  *out = 3; return 0;
}

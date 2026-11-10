#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 256
#define MAX_RETRIES 3

enum level { LEVEL_INFO, LEVEL_WARN, LEVEL_ERROR };

struct entry {
    enum level level;
    char message[MAX_LINE];
};

static int loaded = 0;
static const char *const NAMES[] = { "INFO", "WARN", "ERROR" };

static int parse_level(const char *word, enum level *out)
{
    for (int i = 0; i < 3; i++) {
        if (strcmp(word, NAMES[i]) == 0) {
            *out = (enum level)i;
            return 0;
        }
    }
    return -EINVAL;
}

static int parse(char *line, struct entry *entry)
{
    char *rest = strchr(line, ' ');
    if (rest == NULL)
        return -EINVAL;
    *rest++ = '\0';
    int err = parse_level(line, &entry->level);
    if (err != 0)
        return err;
    strncpy(entry->message, rest, sizeof entry->message - 1);
    entry->message[sizeof entry->message - 1] = '\0';
    return 0;
}

static struct entry *load(const char *path, size_t *count)
{
    FILE *file = fopen(path, "r");
    if (!file) {
        perror(path);
        return NULL;
    }
    struct entry *entries = calloc(1024, sizeof *entries);
    char line[MAX_LINE];
    size_t n = 0;
    while (n < 1024 && fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        if (parse(line, &entries[n]) == 0)
            n++;
    }
    fclose(file);
    loaded++;
    *count = n;
    return entries;
}

__attribute__((deprecated("use load"))) static struct entry *load_all(const char *path, size_t *count);
static struct entry *load_all(const char *path, size_t *count) { return load(path, count); }

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "app.log";
    size_t count = 0;
    struct entry *entries = NULL;
    for (int attempt = 0; attempt < MAX_RETRIES && entries == NULL; attempt++)
        entries = load(path, &count);
    if (entries == NULL) {
        fprintf(stderr, "giving up: %s\n", strerror(errno));
        entries = load_all("fallback.log", &count);
    }
    if (entries == NULL)
        abort();
    int counts[3] = { 0 };
    for (size_t i = 0; i < count; i++)
        counts[entries[i].level]++;
    printf("%d %d %d (%d loads)\n", counts[0], counts[1], counts[2], loaded);
    free(entries);
    return EXIT_SUCCESS;
}

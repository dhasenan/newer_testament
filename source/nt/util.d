module nt.util;

import std.experimental.logger;
import std.uni;

/// A wrapper around std.getopt to make it less terrible
void argparse(T...)(string[] args, string description, T opts)
{
    import core.stdc.stdlib : exit;
    import std.getopt;
    import std.stdio;
    try
    {
        auto gopts = getopt(args,
                config.bundling,
                config.caseSensitive,
                opts);
        if (gopts.helpWanted)
        {
            defaultGetoptPrinter(description, gopts.options);
            exit(0);
        }
    }
    catch (Exception e)
    {
        stderr.writeln(e.message);
        exit(1);
    }
}

/// Separators to use for newline / new paragraph as needed
// Note: these *must* be in the ASCII range because the NLP layer interacts poorly with multibyte
// characters
enum : string { newParagraphMark = "#", newLineMark = "%" }

struct Interval
{
    this(ulong min, ulong max)
    {
        this.min = min;
        this.max = max;
    }
    this(string formatted)
    {
        import std.conv : to;
        import std.algorithm.iteration : splitter;

        auto s = formatted.splitter('-');
        min = s.front.to!ulong;
        s.popFront;
        if (s.empty)
            max = min;
        else
            max = s.front.to!ulong;
    }

    ulong min, max;

    ulong[] all() inout
    {
        import std.range : iota;
        import std.array : array;
        return iota(min, max + 1).array;
    }

    ulong uniform()()
    {
        static import std.random;
        return std.random.uniform(min, max + 1);
    }

    ulong uniform(TRng)(TRng rng)
    {
        static import std.random;
        return std.random.uniform(min, max + 1, rng);
    }

    string toString() const
    {
        import std.format;
        return format("%s-%s", min, max);
    }
}

/**
  */
string matchCase(string cloneFrom, string cloneTo)
{
    ulong upper = 0;
    foreach (dchar d; cloneFrom)
    {
        if (isUpper(d)) upper++;
        if (upper > 1) break;
    }
    // cloneTo might be a proper noun while cloneFrom isn't (eg earth vs Teegeeack)
    if (upper == 0) return cloneTo;
    if (upper == 1) return cloneTo.titleCase;
    return cloneTo.toUpper;
}

unittest
{
    void test(string from, string to, string expected)
    {
        import std.format;
        auto s = matchCase(from, to);
        assert(s == expected, "expected: %s got: %s".format(expected, s));
    }
    test("I", "you", "You");
    test("i", "you", "you");
    test("WE", "you", "YOU");
    test("we", "you", "you");
    test("We", "YOu", "You");
}

string titleCase(string word)
{
    import std.algorithm;
    import std.array;
    import std.conv;
    // TODO reduce allocations if it's already in title case
    return word
        .splitter(" ")
        .map!(x => x[0..1].toUpper ~ x[1 .. $].toLower)
        .joiner(" ")
        .array
        .to!string;
    /*
    static import std.utf;
    import std.conv : to;
    auto rest = word;
    size_t index = 0;
    auto f = std.utf.decodeFront(rest, index);
    return [f].to!string.toUpper ~ word[index .. $].toLower;
    */
}

unittest
{
    void test(string word, string expected)
    {
        import std.format;
        auto s = word.titleCase;
        assert(s == expected, "expected: %s got: %s".format(expected, s));
    }
    test("i", "I");
    test("I", "I");
    test("we", "We");
    test("WE", "We");
    test("wE", "We");
    test("We", "We");
    test("king brown", "King Brown");
}

/**
 * Build a forward range over the words in the given string.
 *
 * The elements of the range are WordFragment structs, carrying both the text and the position in
 * the input they appear, to allow for efficient replacement.
 */
WordFragmentRange toWords(string s)
{
    return WordFragmentRange(s);
}

struct WordFragmentRange
{
    private
    {
        string s;
        // index into the string of where to start the next thingy
        size_t loc;
        WordFragment _curr;
    }

    WordFragment front()
    {
        if (_curr == WordFragment.init && loc == 0) popFront;
        return _curr;
    }

    void popFront()
    {
        _curr = WordFragment.init;
        WordFragment f;
        f.start = size_t.max;
        foreach (size_t i, dchar c; s[loc .. $])
        {
            if (f.start == size_t.max && isWordChar(c))
            {
                f.start = loc + i;
            }
            else if (f.start != size_t.max && !isWordChar(c))
            {
                f.word = s[f.start .. loc + i];
                loc = f.end;
                _curr = f;
                return;
            }
        }
        if (f.start != size_t.max)
        {
            f.word = s[f.start .. $];
            _curr = f;
        }
        else
        {
            _curr = WordFragment.init;
        }
        loc = s.length;
    }

    bool empty() { return loc >= s.length && _curr == WordFragment.init; }

    private bool isWordChar(dchar c)
    {
        import std.uni;
        return std.uni.isAlpha(c);
    }

    WordFragmentRange save() { return this; }
}

struct WordFragment
{
    string word;
    alias word this;
    size_t start;
    size_t end() { return start + word.length; }
    string toString() const
    {
        import std.format;
        return "WordFragment(%s, %s)".format(start, word);
    }
}

unittest
{
    auto s = "Whether 'tis nobler -- in the mind -- to suffer??";
    auto w = s.toWords;
    assert(w.front == WordFragment("Whether", 0), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("tis", 9), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("nobler", 13), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("in", 23), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("the", 26), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("mind", 30), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("to", 38), w.front.toString);
    w.popFront;
    assert(!w.empty);
    assert(w.front == WordFragment("suffer", 41), w.front.toString);
    w.popFront;
    assert(w.empty, w.front.toString);
}

unittest
{
    auto w = "hi".toWords;
    assert(!w.empty);
    assert(w.front.word == "hi", w.front.word);
    w.popFront;
    assert(w.empty);
}

unittest
{
    auto w = "hi there".toWords;
    assert(!w.empty);
    assert(w.front.word == "hi", w.front.word);
    w.popFront;
    assert(!w.empty);
    assert(w.front.word == "there", "expected: [there] got: [" ~ w.front.word ~ "]");
}

string mmap(string filename)
{
    import core.sys.posix.fcntl;
    import mman = core.sys.linux.sys.mman;
    import core.sys.posix.unistd;
    import std.exception : assumeUnique;
    import std.string : toStringz;
    import core.stdc.stdio : SEEK_END, SEEK_SET;
    import core.stdc.errno;
    import core.sys.posix.fcntl : O_RDONLY;

    int fd = open(filename.toStringz, O_RDONLY);
    auto len = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    void* p = mman.mmap(null, len, mman.PROT_READ, mman.MAP_PRIVATE, fd, 0);
    auto err = errno;
    tracef("mmap: ptr %x, err %s, length %s for fd %s", p, err, len, fd);
    if (p == cast(void*)-1)
    {
        import std.conv : to;
        throw new Exception("mmap failed with err " ~ err.to!string);
    }
    return assumeUnique((cast(char*)p)[0 .. len]);
}


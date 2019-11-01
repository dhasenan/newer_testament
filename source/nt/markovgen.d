/** Generator for the markov model. */
module nt.markovgen;

import nt.books;
import nt.themes;

import jsonizer;
import markov;

import core.time;
import std.algorithm;
import std.experimental.logger;
import std.file;
import std.getopt;
import std.json;
import std.random;
import std.range;
import std.stdio;
import std.string;

enum nameStart = "{", nameEnd = "}", chapterStart = "<<<", chapterEnd = ">>>";

void bakeBiblesMain(string[] args)
{
    string model;
    string[] inputs;
    ulong minThreshold = 20;
    ulong maxThreshold = 1000;

    string verseThemeArg = "1-3";
    string nameArg = "1-3";
    auto opts = getopt(args,
            std.getopt.config.required,
            "m|model", "model name to build", &model,
            "i|inputs", "input bibles (JSON) to build model from", &inputs,
            "V|verse-range",
                "how many verses of context to use in verse model",
                &verseThemeArg,
            "n|name-range", "how many letters of context to use in name model", &nameArg,
            "min-threshold",
                "minimum number of word occurrences to consider something a theme",
                &minThreshold,
            "max-threshold",
                "maximum number of word occurrences to consider something a theme",
                &maxThreshold);

    if (opts.helpWanted)
    {
        defaultGetoptPrinter("generate a randomized bible", opts.options);
        return;
    }

    import std.file : mkdirRecurse;
    auto outpath = "models/" ~ model;
    mkdirRecurse(outpath);

    auto verses = MarkovChain!string(Interval(verseThemeArg).all);
    ThemeModel themes;
    themes.minOccurrences = minThreshold;
    themes.maxOccurrences = maxThreshold;
    Bible[] bibles;

    foreach (input; inputs)
    {
        auto bible = readJSON!Bible(input);
        themes.build(bible);
        bibles ~= bible;
    }

    writeJSON(outpath ~ "/histogram.json", themes);

    foreach (bible; bibles)
    {
        foreach (book; bible.books)
        {
            foreach (chapter; book.chapters)
            {
                auto themeSequence =
                    chapter.verses
                        .map!(x => themes.theme(x.text))
                        .filter!(x => x.length > 0)
                        .array;
                verses.train([chapterStart] ~ themeSequence ~ [chapterEnd]);
            }
        }
    }
    verses.encodeBinary(File(outpath ~ "/verses.chain", "w"));

    auto names = MarkovChain!string(Interval(nameArg).all);
    foreach (bible; bibles)
    {
        foreach (book; bible.books)
        {
            names.train([nameStart] ~ book.name.split("") ~ [nameEnd]);
        }
    }
    names.encodeBinary(File(outpath ~ "/names.chain", "w"));
}

struct Interval
{
    this(string s)
    {
        import std.algorithm, std.conv;
        auto p = s.splitter("-");
        min = p.front.to!uint;
        p.popFront;
        if (p.empty)
            max = min;
        else
            max = p.front.to!uint;
    }

    uint min, max;

    uint uniform()
    {
        import std.random : uniform;
        return uniform(min, max + 1);
    }

    uint uniform(TRng)(ref TRng rand)
    {
        import std.random : uniform;
        return uniform(min, max + 1, rand);
    }

    size_t[] all()
    {
        import std.range : iota;
        import std.array : array;
        return iota(cast(size_t)min, cast(size_t)max+1).array;
    }
}

void generateBibleMain(string[] args)
{
    ulong timeout = 300;
    string model;
    uint seed = unpredictableSeed;
    string name = "Book of Squid";
    string outfile = "";
    string epubFile = "";
    ulong history = 1000;

    string bookArg = "8-55";
    string chapterArg = "5-50";
    string verseArg = "12-150";
    string paragraphArg = "4-10";
    auto opts = getopt(args,
            std.getopt.config.required,
            "m|model", "model name to use", &model,
            "s|seed", "random seed", &seed,
            "n|name", "name of the Bible to generate", &name,
            "b|books", "range of books to generate", &bookArg,
            "p|paragraphs", "range of verses per paragraph", &paragraphArg,
            "o|output", "output filename (defaults to name.json)", &outfile,
            "e|epub", "epub filename (defaults to name.epub)", &epubFile,
            "c|chapters", "range of chapters to generate per book", &chapterArg,
            "V|verses", "range of verses to generate per chapter", &verseArg,
            "t|timeout", "how long (in seconds) to spend generating", &timeout,
            "history", "verses of history, to prevent repeats", &history);

    if (opts.helpWanted)
    {
        defaultGetoptPrinter("generate a randomized bible", opts.options);
        return;
    }

    rndGen.seed(seed);
    tracef("seed %s", seed);
    Random breaker;
    breaker.seed(seed);

    auto bookCount = Interval(bookArg);
    auto chapterCount = Interval(chapterArg);
    auto verseCount = Interval(verseArg);
    auto paragraphCount = Interval(paragraphArg);

    auto modelPath = "models/" ~ model;

    trace("loading model file");
    auto verses = decodeBinary!string(File(modelPath ~ "/verses.chain", "r"));
    auto names = decodeBinary!string(File(modelPath ~ "/names.chain", "r"));
    trace("loading histogram");
    auto themes = readJSON!ThemeModel(modelPath ~ "/histogram.json");
    themes.shuffle(seed);
    themes.historyLength = history;
    trace("loaded histogram");

    import std.datetime.systime;
    import std.random;

    auto limit = Clock.currTime + timeout.seconds;

    Bible bible;
    bible.name = name;
    auto numBooks = bookCount.uniform;
    foreach (booknum; 0 .. numBooks)
    {
        Book book;
        import std.format : format;

        names.reset;
        names.seed(nameStart);
        Appender!string namegen;
        foreach (i; 0 .. 25)
        {
            auto c = names.generate;
            if (c == nameEnd) break;
            if (c == nameStart) continue;
            namegen ~= c;
        }
        book.name = namegen.data;

        auto numChapters = chapterCount.uniform;
        foreach (chapternum; 0 .. numChapters)
        {
            verses.reset;
            verses.seed(chapterStart);
            Chapter chapter;
            chapter.chapter = chapternum + 1;
            auto vv = verses.generate(verseCount.uniform)
                .map!(x => themes.toVerse(x))
                // Remove whitespace
                .map!(x => x.strip)
                // Make sure we don't have any empty verses
                .filter!(x => x.length > 0)
                .map!(x => Verse(0, x))
                .array;
            uint kept = 0;
            ulong nextPara = paragraphCount.uniform(breaker);
            foreach (i, v; vv)
            {
                if (v.text.length == 0)
                {
                    // This shouldn't happen. It really shouldn't. It does, though, and I don't know
                    // why.
                    tracef("somehow got an empty verse??");
                }
                else if (v.text == chapterEnd)
                {
                    break;
                }
                else
                {
                    kept++;
                    if (v.text.canFind("\u2029"))
                    {
                        nextPara = i + paragraphCount.uniform(breaker);
                    }
                    else if (i == nextPara)
                    {
                        v.text ~= "\u2029";
                        nextPara = i + paragraphCount.uniform(breaker);
                    }
                    v.verse = kept;
                    chapter.verses ~= v;
                }
            }
            book.chapters ~= chapter;
            if (Clock.currTime > limit)
            {
                trace("exceeded time limit; aborting early");
                bible.books ~= book;
                goto save;
            }
            tracef("built book %s/%s chapter %s/%s", booknum + 1, numBooks, chapternum + 1,
                    numChapters);
        }
        bible.books ~= book;
    }
save:
    if (outfile == "")
    {
        outfile = name ~ ".json";
    }
    writeJSON(outfile, bible);
    import nt.publish;
    if (epubFile == "")
    {
        epubFile = name ~ ".epub";
    }
    writeEpub(bible, epubFile);
}

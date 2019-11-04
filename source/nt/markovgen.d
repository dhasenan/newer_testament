/** Generator for the markov model. */
module nt.markovgen;

import nt.books;
import nt.names;
import nt.themes;
import nt.util;
import nt.wiktionary;

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
    auto nameChain = MarkovChain!string(Interval(nameArg).all);
    ThemeModel themes;
    themes.minOccurrences = minThreshold;
    themes.maxOccurrences = maxThreshold;
    Bible[] bibles;

    ulong[string] nameHistogram;
    foreach (input; inputs)
    {
        auto text = input.readText;
        auto bible = fromJSONString!Bible(text);
        tracef("bible %s length %s has %s books", bible.name, text.length, bible.books.length);
        findNames(bible, nameHistogram);
        bibles ~= bible;
    }
    tracef(
            "read %s bibles, %s names",
            bibles.length,
            nameHistogram.length);

    writeJSON(outpath ~ "/names.json", nameHistogram);
    tracef("training character names");
    foreach (name, v; nameHistogram)
    {
        nameChain.train(name.toLower.split(""));
    }
    nameChain.encodeBinary(File(outpath ~ "/charnames.chain", "w"));

    auto inputPath = outpath ~ "/inputs";
    mkdirRecurse(inputPath);
    tracef("removing names to protect the guilty");
    foreach (i, bible; bibles)
    {
        convertNames(bible, nameHistogram);
        // Save the converted forms into our model area for posterity
        import std.format : format;
        writeJSON(format("%s/%s.json", inputPath, i), bible);
    }

    tracef("finding themes");
    foreach (i, bible; bibles)
    {
        themes.build(bible);
    }
    writeJSON(outpath ~ "/themes.json", themes);

    tracef("training theme sequences");
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
            tracef("trained %s book %s", bible.name, book.name);
        }
    }
    verses.encodeBinary(File(outpath ~ "/verses.chain", "w"));

    tracef("training book names");
    auto names = MarkovChain!string(Interval(nameArg).all);
    foreach (bible; bibles)
    {
        foreach (book; bible.books)
        {
            names.train([nameStart] ~ book.name.split("") ~ [nameEnd]);
        }
    }
    names.encodeBinary(File(outpath ~ "/booknames.chain", "w"));
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
    double chapterFactor = 3, bookFactor = 4;
    string dbFilename;
    double synonymFactor = 0.2;

    string bookArg = "8-55";
    string chapterArg = "5-50";
    string verseArg = "12-150";
    string paragraphArg = "2-12";
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
            "chapter-character-ratio", "multiplier for dramatis personae per chapter",
            &chapterFactor,
            "book-character-ratio", "multiplier for dramatis personae per book", &bookFactor,
            "V|verses", "range of verses to generate per chapter", &verseArg,
            "t|timeout", "how long (in seconds) to spend generating", &timeout,
            "d|synonym-db",
                "location of synonyms db (omit to not use synonym replacement)",
                &dbFilename,
            "synonym-factor", "percentage of words to replace with a synonym", &synonymFactor,
            "history", "verses of history, to prevent repeats", &history);

    if (opts.helpWanted)
    {
        defaultGetoptPrinter("generate a randomized bible", opts.options);
        return;
    }

    if (chapterFactor < 1)
    {
        chapterFactor = 1 + (chapterFactor - cast(long)chapterFactor);
    }
    if (bookFactor < 1)
    {
        bookFactor = 1 + (bookFactor - cast(long)bookFactor);
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
    auto bookNames = decodeBinary!string(File(modelPath ~ "/booknames.chain", "r"));
    auto charNames = decodeBinary!string(File(modelPath ~ "/charnames.chain", "r"));
    trace("loading themes");
    auto themes = readJSON!ThemeModel(modelPath ~ "/themes.json");
    themes.shuffle(seed);
    themes.historyLength = history;
    trace("loaded themes");

    import std.datetime.systime;
    import std.random;

    // markov doesn't allow you to plug in your own RNG, so we need to seed the RNG multiple times
    rndGen.seed(seed);
    Random nameGen;
    nameGen.seed(seed);
    auto people = iota(500)
        .map!(x => charNames.generate(uniform(4, 10)).join(""))
        .map!titleCase
        .array
        .sort
        .uniq
        .array;

    auto limit = Clock.currTime + timeout.seconds;

    rndGen.seed(seed);
    Bible bible = new Bible;
    bible.name = name;
    auto numBooks = bookCount.uniform;
    bool[string] usedBookNames;
    foreach (booknum; 0 .. numBooks)
    {
        Book book = new Book;
        import std.format : format;

        foreach (attempt; 0 .. 10)
        {
            bookNames.reset;
            bookNames.seed(nameStart);
            Appender!string namegen;
            foreach (i; 0 .. 25)
            {
                auto c = bookNames.generate;
                if (c == nameEnd) break;
                if (c == nameStart) continue;
                namegen ~= c;
            }
            book.name = namegen.data;
            if (book.name in usedBookNames) continue;
            usedBookNames[book.name] = true;
            break;
        }

        auto numChapters = chapterCount.uniform;
        foreach (chapternum; 0 .. numChapters)
        {
            import std.string : strip;
            verses.reset;
            verses.seed(chapterStart);
            Chapter chapter = new Chapter;
            chapter.chapter = cast(uint)(chapternum + 1);
            auto vv = verses.generate(verseCount.uniform)
                .map!(x => themes.toVerse(x))
                // Remove whitespace
                .map!(x => x.strip)
                // Make sure we don't have any empty verses
                .filter!(x => x.length > 0)
                .map!(x => new Verse(0, x))
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
    swapNames(bible, people, chapterFactor, bookFactor);

    if (dbFilename)
    {
        rndGen.seed(seed);
        tracef("spicing things up with synonyms");
        auto db = new DB(dbFilename);
        replaceSynonyms(db, bible, synonymFactor);
        db.cleanup;
    }

    if (outfile == "")
    {
        outfile = name ~ ".json";
    }
    tracef("saving bible json to %s", outfile);
    writeJSON(outfile, bible);

    import nt.publish;
    if (epubFile == "")
    {
        epubFile = name ~ ".epub";
    }
    tracef("building ebook at %s", epubFile);
    writeEpub(bible, epubFile);
}


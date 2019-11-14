/** Generator for the markov model. */
module nt.markovgen;

import nt.books;
import nt.db;
import nt.names;
import nt.nlp;
import nt.themes;
import nt.util;
import nt.wiktionary;
import nt.dictionary;

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

enum nameStart = "{", nameEnd = "}";

void buildThemeChain(Bible bible, string outputChain, Interval verseContext)
{
    auto verses = MarkovChain!string(verseContext.all);
    foreach (book; bible.books)
    {
        foreach (chapter; book.chapters)
        {
            auto themeSequence =
                chapter.verses
                .map!(x => x.theme)
                .filter!(x => x.length > 0)
                .array;
            verses.train([nameStart] ~ themeSequence ~ [nameEnd]);
        }
        tracef("trained %s book %s", bible.name, book.name);
    }
    verses.encodeBinary(File(outputChain, "w"));
}

void buildNameChain(Bible bible, string outputChain, Interval nameContext)
{
    auto nameChain = MarkovChain!string(nameContext.all);
    foreach (name, v; bible.nameHistogram)
    {
        nameChain.train([nameStart] ~ name.toLower.split("") ~ [nameEnd]);
    }
    nameChain.encodeBinary(File(outputChain, "w"));
}

string genName(ref MarkovChain!string chain, Interval length)
{
    import std.array;
    enum maxAttempts = 10;
    Appender!string a;
    foreach (i; 0 .. maxAttempts)
    {
        a = typeof(a).init;
        chain.reset;
        chain.seed(nameStart);
        foreach (j; 0 .. length.max)
        {
            auto c = chain.generate;
            if (c == nameEnd)
            {
                auto d = a.data;
                if (d.length in length)
                {
                    return d;
                }
                break;
            }
            a ~= c;
        }
    }
    return a.data;
}

void bakeBiblesMain(string[] args)
{
    string model;
    string[] inputs;

    string verseThemeArg = "1-3";
    string nameArg = "1-3";
    string themeThresholdArg = "20-1000";
    auto originalArgs = args;
    auto opts = getopt(args,
            std.getopt.config.required,
            "m|model", "model name to build", &model,
            "i|inputs", "input bibles (JSON) to build model from", &inputs,
            "V|verse-range",
                "how many verses of context to use in verse model",
                &verseThemeArg,
            "n|name-range", "how many letters of context to use in name model", &nameArg);

    if (opts.helpWanted)
    {
        defaultGetoptPrinter("generate a randomized bible", opts.options);
        return;
    }

    import std.file : mkdirRecurse;
    auto outpath = "models/" ~ model;
    mkdirRecurse(outpath);
    auto inputPath = outpath ~ "/inputs";
    mkdirRecurse(inputPath);
    import std.path;
    std.file.write(buildPath(outpath, "args"), originalArgs.join("\n"));

    auto verses = MarkovChain!string(Interval(verseThemeArg).all);
    auto nameChain = MarkovChain!string(Interval(nameArg).all);
    Bible[] bibles;

    ulong[string] nameHistogram;
    auto nlp = new NLP;
    foreach (input; inputs)
    {
        auto bible = readJSON!Bible(input);
        tracef("bible %s has %s books", bible.name, bible.books.length);
        bibles ~= bible;
        foreach (name, freq; bible.nameHistogram)
        {
            if (auto p = name in nameHistogram)
            {
                (*p) += freq;
            }
            else
            {
                nameHistogram[name] = freq;
            }
        }
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

    tracef("training theme sequences");
    foreach (bible; bibles)
    {
        foreach (book; bible.books)
        {
            foreach (chapter; book.chapters)
            {
                auto themeSequence =
                    chapter.verses
                        .map!(x => x.theme)
                        .filter!(x => x.length > 0)
                        .array;
                verses.train([nameStart] ~ themeSequence ~ [nameEnd]);
            }
            //tracef("trained %s book %s", bible.name, book.name);
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

struct BibleConfig
{
    mixin JsonizeMe;
    @jsonize
    {
        string name = "Poorman's Infinite Bible";
        string input;
        string dictionaryDatabase = "dict.sqlite3";
        double chapterCharacterFactor = 3;
        double bookCharacterFactor = 4;
        ulong history = 1000;
        double synonymFactor = 0.2;
        double antonymFactor = 0.05;
    }
    @jsonize("books")
    {
        string booksArg() { return books.toString(); }
        void booksArg(string s) { books = Interval(s); }
    }
    @jsonize("chapters")
    {
        string chaptersArg() { return chapters.toString(); }
        void chaptersArg(string s) { chapters = Interval(s); }
    }
    @jsonize("verses")
    {
        string versesArg() { return verses.toString(); }
        void versesArg(string s) { verses = Interval(s); }
    }
    @jsonize("paragraphLength")
    {
        string paragraphLengthArg() { return paragraphLength.toString(); }
        void paragraphLengthArg(string s) { paragraphLength = Interval(s); }
    }
    Interval books = Interval(5, 22);
    Interval chapters = Interval(3, 50);
    Interval verses = Interval(12, 90);
    Interval paragraphLength = Interval(3, 12);

    void clear()
    {
        foreach (i, a; this.tupleof)
        {
            this.tupleof[i] = typeof(a).init;
        }
    }

    void acceptOverlay(const ref BibleConfig other)
    {
        foreach (i, a; other.tupleof)
        {
            if (a !is typeof(a).init)
            {
                this.tupleof[i] = a;
            }
        }
    }

    void adjustPathsRelativeTo(string dir)
    {
        import std.path;
        if (input)
            input = absolutePath(input, dir);
        if (dictionaryDatabase)
            dictionaryDatabase = absolutePath(dictionaryDatabase, dir);
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
    foreach (person; people) bible.nameHistogram[person] = 0;
    auto numBooks = bookCount.uniform;
    bool[string] usedBookNames;
    foreach (booknum; 0 .. numBooks)
    {
        Book book = new Book;
        import std.format : format;

        foreach (attempt; 0 .. 10)
        {
            book.name = genName(bookNames, Interval(4, 20));
            if (book.name in usedBookNames) continue;
            usedBookNames[book.name] = true;
            break;
        }

        auto numChapters = chapterCount.uniform;
        foreach (chapternum; 0 .. numChapters)
        {
            import std.string : strip;
            verses.reset;
            verses.seed(nameStart);
            Chapter chapter = new Chapter;
            chapter.chapter = cast(uint)(chapternum + 1);
            uint kept = 0;
            ulong nextPara = paragraphCount.uniform(breaker);
            foreach (theme; verses.generate(verseCount.uniform))
            {
                if (theme.length == 0) continue;
                if (theme == nameEnd) break;
                auto v = themes.toVerse(theme);
                if (v is null) continue;
                if (v.analyzed.length == 0) continue;
                kept++;
                foreach (lex; v.analyzed)
                {
                    if (lex.word == nameEnd) break;
                    if (lex.word == newParagraphMark)
                    {
                        nextPara = kept + paragraphCount.uniform(breaker);
                    }

                }
                if (kept == nextPara)
                {
                    auto lex = new Lex;
                    lex.word = newParagraphMark;
                    lex.inflect = "_SP";
                    lex.person = -1;
                    v.analyzed ~= lex;
                }
                v.verse = cast(uint)chapter.verses.length + 1;
                chapter.verses ~= v;
            }
            book.chapters ~= chapter;
            tracef("built book %s/%s chapter %s/%s", booknum + 1, numBooks, chapternum + 1,
                    numChapters);
        }
        bible.books ~= book;
    }
save:
    import std.path : buildPath;

    writeJSON(buildPath(modelPath, "gen-nlp-prename-%s.json".format(seed)), bible);

    swapNames(bible, people, chapterFactor, bookFactor);

    writeJSON(buildPath(modelPath, "gen-nlp-presynonym-%s.json".format(seed)), bible);

    if (dbFilename)
    {
        rndGen.seed(seed);
        tracef("spicing things up with synonyms");
        auto db = new DB(dbFilename);
        replaceSynonyms(db, bible, synonymFactor);
        db.cleanup;
    }

    writeJSON(buildPath(modelPath, "gen-nlp-only-%s.json".format(seed)), bible);

    import nt.nlp;
    new NLP().render(bible);

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


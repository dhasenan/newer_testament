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
import std.conv : to;
import std.experimental.logger;
import std.file;
import std.getopt;
import std.json;
import std.random;
import std.range;
import std.stdio;
import std.string;

enum nameStart = "{", nameEnd = "}";

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
    string database;
    ulong modelId;

    string verseThemeArg = "1-3";
    string nameArg = "1-3";
    string themeThresholdArg = "20-1000";
    auto opts = getopt(args,
            std.getopt.config.required,
            "d|database", "database path", &database,
            std.getopt.config.required,
            "m|model", "ID of model name", &modelId,
            "V|verse-range",
                "how many verses of context to use in verse model",
                &verseThemeArg,
            "n|name-range", "how many letters of context to use in name model", &nameArg);

    if (opts.helpWanted)
    {
        defaultGetoptPrinter("generate a randomized bible", opts.options);
        return;
    }

    auto db = new DB(database);
    scope (exit) db.cleanup;

    auto model = db.get!ThemeModel(modelId);

    auto verses = MarkovChain!string(Interval(verseThemeArg).all);
    auto nameChain = MarkovChain!string(Interval(nameArg).all);
    auto bookNameChain = MarkovChain!string(Interval(nameArg).all);

    foreach (book; db.booksByBible(model.bibleId))
    {
        bookNameChain.train([nameStart] ~ book.name.split("") ~ [nameEnd]);
        auto sentences = db.sentencesByBook(book.id, model.id);
        Appender!(string[]) a;
        a ~= nameStart;
        foreach (s; sentences)
        {
            a ~= s.token;
        }
        a ~= nameEnd;
        verses.train(a.data);
    }
    model.bookChain = bookNameChain.encodeBinary;
    model.verseChain = verses.encodeBinary;

    auto bible = db.get!Bible(model.bibleId);
    foreach (name, freq; bible.nameHistogram)
    {
        nameChain.train([nameStart] ~ name.split("") ~ [nameEnd]);
    }
    model.characterChain = nameChain.encodeBinary;

    db.save(model);
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
    ulong modelId;
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
    string database;
    auto opts = getopt(args,
            std.getopt.config.required,
            "d|database", "database name", &database,
            std.getopt.config.required,
            "m|modelid", "model id to use", &modelId,
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

    auto db = new DB(database);
    scope (exit) db.cleanup;
    auto model = db.get!ThemeModel(modelId);

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

    auto modelPath = "models/" ~ model.id.to!string;

    trace("loading markov chains");
    auto verses = decodeBinary!string(model.verseChain);
    auto bookNames = decodeBinary!string(model.bookChain);
    auto charNames = decodeBinary!string(model.characterChain);
    trace("loading themes");
    auto themes = db.get!ThemeModel(modelId);
    themes.rng.seed(seed);
    trace("loaded themes");

    import std.datetime.systime;
    import std.random;

    // markov doesn't allow you to plug in your own RNG, so we need to seed the RNG multiple times
    rndGen.seed(seed);
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
    db.save(bible);
    foreach (person; people) bible.nameHistogram[person] = 0;
    auto numBooks = bookCount.uniform;
    bool[string] usedBookNames;
    foreach (booknum; 0 .. numBooks)
    {
        Book book = new Book;
        book.bibleId = bible.id;

        foreach (attempt; 0 .. 10)
        {
            book.name = genName(bookNames, Interval(4, 20));
            if (book.name in usedBookNames) continue;
            usedBookNames[book.name] = true;
            break;
        }
        db.save(book);

        auto numChapters = chapterCount.uniform;
        foreach (chapternum; 0 .. numChapters)
        {
            import std.string : strip;
            verses.reset;
            verses.seed(nameStart);
            version (jsonSave)
            {
                Chapter chapter = new Chapter;
                chapter.chapter = cast(uint)(chapternum + 1);
                book.chapters ~= chapter;
            }
            uint kept = 0;
            ulong nextPara = paragraphCount.uniform(breaker);
            ulong generated = 0;
            foreach (theme; verses.generate(verseCount.uniform))
            {
                if (theme.length == 0) continue;
                if (theme == nameEnd)
                {
                    if (generated in verseCount)
                    {
                        // We've reached our goal!
                        break;
                    }
                    // We have some more space, let's continue.
                    continue;
                }
                // Probably won't happen, but let's be cautious.
                if (theme == nameStart) continue;
                auto v = findFreeSentence(model, db, theme);
                if (v is null) continue;
                if (v.analyzed.length == 0) continue;
                kept++;
                generated++;
                v.chapterNum = chapternum + 1;
                v.bookId = book.id;
                v.verse = generated;
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
                    kept = 0;
                }
                version (jsonSave) chapter.verses ~= v;
                db.save(v);
            }
        }
        tracef("built book %s/%s", booknum + 1, numBooks);
        version (jsonSave) bible.books ~= book;
    }

    import std.path : buildPath;

    version (jsonSave)
        writeJSON(buildPath(modelPath, "gen-nlp-prename-%s.json".format(seed)), bible);

    //swapNames(bible, people, chapterFactor, bookFactor);
    warning("name swapping to be implemented");

    version (jsonSave)
        writeJSON(buildPath(modelPath, "gen-nlp-presynonym-%s.json".format(seed)), bible);

    rndGen.seed(seed);
    tracef("spicing things up with synonyms");
    replaceSynonyms(db, bible, synonymFactor);

    version (jsonSave)
        writeJSON(buildPath(modelPath, "gen-nlp-only-%s.json".format(seed)), bible);

    import nt.nlp;
    new NLP().render(bible);

    if (outfile == "")
    {
        outfile = name ~ ".json";
    }
    version (jsonSave)
    {
        tracef("saving bible json to %s", outfile);
        writeJSON(outfile, bible);
    }

    import nt.publish;
    if (epubFile == "")
    {
        epubFile = name ~ ".epub";
    }
    tracef("building ebook at %s", epubFile);
    writeEpub(bible, epubFile);
}


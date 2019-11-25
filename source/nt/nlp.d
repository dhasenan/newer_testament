module nt.nlp;

import nt.books;
import nt.db;

import pyd.pyd;
import pyd.embedded;
import pyd.pydobject;

import std.algorithm;
import std.conv;
import std.experimental.logger;
import std.uuid;

class NLP
{
    shared static this()
    {
        py_init();
    }

    this()
    {
        PydObject spacy = py_import("spacy");
        PydObject load = spacy.load;
        this.nlp = load("en_core_web_lg");
        this.getInflection = py_import("pyinflect").getInflection;
        PydObject builtins = py_import("builtins");
        this.strType = builtins.str;
        this.tupleType = builtins.tuple;
    }

    private PydObject nlp, getInflection, strType, tupleType;

    void analyzeSentences(Bible bible)
    {
        foreach (book; bible.books)
        {
            foreach (chapter; book.chapters)
            {
                import std.algorithm;
                import std.conv;
                auto text = chapter.verses.map!(x => x.text).joiner(" ").to!string;
                chapter.sentences = analyzeSentences(text);
            }
        }
    }

    Sentence[] analyzeSentences(string text)
    {
        auto doc = nlp(text);
        Sentence[] sentences;
        foreach (PydObject span; doc.sents)
        {
            auto s = new Sentence;
            s.raw = asString(span.text);
            auto rootTag = asString(span.root.tag_);
            switch (rootTag)
            {
                case "VBZ":
                case "VBP":
                    s.tense = Tense.present;
                    break;
                case "VBD":
                    s.tense = Tense.past;
                    break;
                case "VBG":
                    s.tense = Tense.progressive;
                    break;
                case "VB":
                    // VB is entirely determined by the auxiliaries.
                    break;
                case "VBN":
                    // VBN is perfect, but not sure which.
                    s.tense = Tense.perfect;
                    break;
                default:
                    warningf("sentence root was a non-verb %s; sentence: %s", rootTag, s.raw);
                    break;
            }
            foreach (child; span.root.children)
            {
                switch (asString(child.tag_))
                {
                    case "MD":
                        // "modal" auxiliary
                        if (asString(child.lemma_) == "will")
                        {
                            // not really modal now are we?
                            s.tense |= Tense.future;
                        }
                        break;
                    case "VBZ":
                    case "VBP":
                        // they have(VBP) run(VBN) very fast:
                        //     present perfect; perfect already marked.
                        // she has(VBZ) run(VBN) very fast:
                        //     present perfect; perfect already marked.
                        // they have(VBP) been(VBN) running(VBG):
                        //     present perfect progressive
                        //     progressive marked with main verb
                        //     VBN will mark with perfect
                        s.tense |= Tense.present;
                        break;
                    case "VBD":
                        // present progressive / present perfect
                        s.tense |= Tense.present;
                        break;
                    case "VBN":
                        // they have(VBP) been(VBN) running(VBG):
                        //     present perfect progressive
                        //     progressive marked with main verb
                        //     VBP marked present already
                        s.tense |= Tense.perfect;
                        break;
                    default:
                        // not an auxiliary verb or modal marker
                        break;
                }
            }

            sentences ~= s;
        }
        return sentences;
    }

    void analyze(Bible bible)
    {
        import std.range : enumerate;
        foreach (i, verse; bible.allVerses.enumerate)
        {
            analyze(verse);
            if (i % 1000 == 0)
            {
                tracef("analyzed %s verses", i);
            }
        }
    }

    void analyze(Verse verse)
    {
        verse.analyzed = analyze(verse.text);
    }

    Lex[] analyze(string text)
    {
        auto doc = nlp(text.idup);
        return toLex(doc);
    }

    Lex[] toLex(PydObject doc)
    {
        Lex[] analyzed;
        foreach (i; 0 .. doc.length)
        {
            auto lex = new Lex;
            auto t = doc[i];
            auto text = asString(t.text);
            lex.word = asString(t.lemma_);
            lex.inflect = asString(t.tag_);
            lex.whitespace = asString(t.whitespace_);
            lex.upper = 0;
            foreach (dchar c; text)
            {
                import std.uni : isUpper;
                if (isUpper(c)) lex.upper++;
                if (lex.upper >= 2) break;
            }

            // Detect contractions early
            switch (text)
            {
                // fancy apostrophe versions
                case "n’t":
                case "’ll":
                case "’re":
                // plain apostrophe versions
                case "n't":
                case "'ll":
                case "'re":
                    lex.word = text;
                    break;
                default:
            }

            // "-PRON-" isn't useful, not going to do anything handy with it anyway
            if (lex.word == "-PRON-")
            {
                // make sure it's lower case so it appears in our stopwords collection
                import std.string : toLower;
                lex.word = text.toLower;
                lex.inflect = "-PRON-";
            }
            // What's our inflection variant?
            auto variants = getInflection(
                    lex.word,
                    lex.inflect,
                    // inflect_oov: if you don't have the exact form available, intuit it from rules
                    true);
            if (!variants.not())
            {
                foreach (j; 0 .. variants.length)
                {
                    import std.uni, std.utf;
                    if (icmp(text, asString(variants[j])) == 0)
                    {
                        lex.variant = cast(ubyte)j;
                        break;
                    }
                }
            }
            analyzed ~= lex;
        }
        return analyzed;
    }

    void render(Bible bible)
    {
        import std.range;
        foreach (i, verse; bible.allVerses.enumerate)
        {
            render(verse);
            if (i > 0 && i % 1000 == 0)
            {
                tracef("rendered %s verses", i);
            }
        }
    }

    void render(Verse verse)
    {
        import std.array : Appender;
        Appender!string a;
        foreach (lex; verse.analyzed)
        {
            auto s = getInflection(lex.word, lex.inflect);
            string w;
            if (s.not)
            {
                w = lex.word;
            }
            else if (s.length > lex.variant)
            {
                w = asString(s[lex.variant]);
            }
            else
            {
                w = asString(s[0]);
            }
            import std.uni, std.utf;
            import nt.util;
            switch (lex.upper)
            {
                case 0:
                    a ~= w;
                    break;
                case 1:
                    a ~= w.titleCase;
                    break;
                default:
                    a ~= w.toUpper;
                    break;
            }
            a ~= lex.whitespace;
        }
        verse.text = a.data;
    }

    private string asString(PydObject o)
    {
        import std.utf, std.uni;
        if (o.isinstance(tupleType))
        {
            // hopefully it's a tuple containing only one string?
            o = o[0];
        }
        auto s = o.to_d!string;
        // this uses the replacement character, which we should probably remove later
        // but for now, let's at least signal its presence
        return s.toUTF8; //.replace(replacementDchar, ' ');
    }
}

unittest
{
    auto verse = new Verse;
    verse.text = "And Sarah died in Kirjatharba; the same is Hebron in the land of Canaan";
    auto nlp = new NLP;
    nlp.analyze(verse);
    assert(verse.analyzed.length == 15);
    enum words = ["and", "Sarah", "die", "in", "Kirjatharba", ";", "the", "same", "be", "Hebron",
               "in", "the", "land", "of", "Canaan"];
    enum inflections = ["CC", "NNP", "VBD", "IN", "NNP", ":", "DT", "JJ", "VBZ", "NNP", "IN", "DT",
                     "NN", "IN", "NNP"];
    foreach (i, v; verse.analyzed)
    {
        assert(v.word == words[i], "expected " ~ words[i] ~ ", got " ~ v.word);
        assert(
                v.inflect == inflections[i],
                "expected " ~ inflections[i] ~ ", got " ~ v.inflect);
    }
}


void nlpMain(string[] args)
{
    import std.getopt;
    import nt.util;
    import jsonizer;

    string database;
    ulong bibleId;

    argparse(args,
            "Produce NLP analysis annotations for a bible",
            config.required,
            "b|bible-id", "ID of the Bible to update", &bibleId,
            config.required,
            "d|database", "database to be updated in-place", &database);

    auto nlp = new NLP;
    auto db = new DB(database);
    scope (success) { trace("cleaning up db"); db.cleanup; }

    trace("clearing existing analysis");
    db.beginTransaction;
    db.clearExistingAnalysis(bibleId);
    db.commit;

    trace("finding books");
    db.beginTransaction;
    auto books = db.booksByBible(bibleId);
    trace("paging through chapters");
    foreach (book; books)
    {
        auto max = db.maxChapter(book.id);
        foreach (chapterNum; 1 .. max + 1)
        {
            auto chapter = db.versesByChapter(book.id, chapterNum);
            if (chapter.length == 0) continue;
            tracef("book %s chapter %s has %s verses", book.name, chapterNum, chapter.length);
            auto text = chapter.map!(x => x.text).joiner(" ").to!string;
            tracef("got text");
            Sentence[] sentences;
            try
            {
                sentences = nlp.analyzeSentences(text);
            }
            catch (Throwable e)
            {
                errorf("failed to get sentences: %x; aborting", cast(void*)e);
                break;
            }
            tracef("%s sentences to save", sentences.length);
            foreach (f; sentences[0].tupleof)
            {
                trace(f);
            }
            foreach (i, sentence; sentences)
            {
                sentence.bookId = book.id;
                sentence.chapterNum = chapterNum;
                sentence.offset = i;
                db.save(sentence);
            }
        }
    }
    db.commit;
}

void nlpRenderMain(string[] args)
{
    import std.getopt;
    import nt.util;
    import jsonizer;

    string input, output;

    string database;
    ulong bibleId;

    argparse(args,
            "Render NLP analysis back into text, in-place",
            config.required,
            "b|bible-id", "ID of the Bible to update", &bibleId,
            config.required,
            "d|database", "database to be updated in-place", &database);

    auto nlp = new NLP;
    auto db = new DB(database);
    scope (exit) db.cleanup;

    db.beginTransaction;
    foreach (verse; db.allVerses(bibleId))
    {
        nlp.render(verse);
        db.save(verse);
    }
    db.commit;
}

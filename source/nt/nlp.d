module nt.nlp;

import pyd.pyd;
import pyd.embedded;
import pyd.pydobject;
import nt.books;

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
        this.nlp = load("en_core_web_sm");
        this.getInflection = py_import("pyinflect").getInflection;
        PydObject builtins = py_import("builtins");
        this.strType = builtins.str;
        this.tupleType = builtins.tuple;
    }

    private PydObject nlp, getInflection, strType, tupleType;

    void analyze(Bible bible)
    {
        import std.range : enumerate;
        foreach (i, verse; bible.allVerses.enumerate)
        {
            analyze(verse);
            if (i % 1000 == 0)
            {
                import std.experimental.logger;
                tracef("analyzed %s verses", i);
            }
        }
    }

    void analyze(Verse verse)
    {
        Lex[] lex;
        auto doc = nlp(verse.text.idup);
        foreach (i; 0 .. doc.length)
        {
            auto t = doc[i];
            auto ws = asString(t.whitespace_);
            auto lemma = asString(t.lemma_);
            auto tag = asString(t.tag_);
            if (lemma == "-PRON-")
            {
                lemma = asString(t.text);
                tag = "-PRON-";
            }
            lex ~= Lex(lemma, asString(t.tag_), ws);
        }
        verse.analyzed = lex;
    }

    void render(Bible bible)
    {
        import std.experimental.logger;
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
            if (s.not)
            {
                a ~= lex.word;
            }
            else
            {
                a ~= asString(s);
            }
            a ~= lex.whitespace;
        }
        verse.text = a.data;
    }

    private string asString(PydObject o)
    {
        import std.utf, std.uni;
        import std.experimental.logger;
        tracef("asString called on %s", o.type.__name__.to_d!string);
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

    string input, output;

    argparse(args,
            "Produce NLP analysis annotations for a bible",
            config.required,
            "i|input", "input bible", &input,
            config.required,
            "o|output", "output bible", &output);
    auto nlp = new NLP;
    auto bible = readJSON!Bible(input);
    nlp.analyze(bible);
    writeJSON(output, bible);
}

void nlpRenderMain(string[] args)
{
    import std.getopt;
    import nt.util;
    import jsonizer;

    string input, output;

    argparse(args,
            "Render NLP analysis of a Bible",
            config.required,
            "i|input", "input bible", &input,
            config.required,
            "o|output", "output bible", &output);
    auto nlp = new NLP;
    auto bible = readJSON!Bible(input);
    nlp.render(bible);
    writeJSON(output, bible);
}

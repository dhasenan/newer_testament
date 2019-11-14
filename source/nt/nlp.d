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
        this.nlp = load("en_core_web_lg");
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
        Lex[] analyzed;
        auto doc = nlp(verse.text.idup);
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
        verse.analyzed = analyzed;
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
        import std.experimental.logger;
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

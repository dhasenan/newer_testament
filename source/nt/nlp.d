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
    }

    private PydObject nlp, getInflection;

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
        auto doc = nlp(verse.text);
        foreach (i; 0 .. doc.length)
        {
            auto t = doc[i];
            auto ws = t.text_with_ws.to_d!string[t.text.length .. $];
            lex ~= Lex(t.lemma_.to_d!string, t.tag_.to_d!string, ws);
        }
        verse.analyzed = lex;
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
                a ~= s.to_d!string;
            }
        }
        verse.text = a.data;
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

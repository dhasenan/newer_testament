module nt.dictionary;

import d2sqlite3;
import jsonizer;
import nt.books;
import std.experimental.logger;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

enum PartOfSpeech : string
{
    noun = "noun",
    verb = "verb",
    adjective = "adjective",
    adverb = "adverb",
    preposition = "preposition",
    properNoun = "properNoun"
}

class Word : DBObject
{
    /// The word itself, forced into lowercase
    string word;
    /// What part of speech (noun, verb, adjective, adverb, preposition, proper noun)
    PartOfSpeech partOfSpeech;
    /// Ways to pronounce it, in IPA
    string[] pronunciations;
    ///
    string[] synonyms;
    ///
    string[] antonyms;
    /// More specific versions of this word
    string[] hyponyms;
    /// Less specific versions of this word
    string[] hypernyms;

    void merge(Word other)
    {
        import std.algorithm : sort, uniq;
        import std.array : array;
        foreach (i, v; this.tupleof)
        {
            static if (is(typeof(v) == string[]))
            {
                v ~= other.tupleof[i];
                v = v.sort.uniq.array;
            }
        }
    }

    string randomReplacement()
    {
        import std.random;
        auto count = synonyms.length + antonyms.length + hyponyms.length + hypernyms.length;
        if (count == 0) return word;
        auto r = uniform(0, count);
        if (r < synonyms.length) return synonyms[r];
        r -= synonyms.length;
        if (r < antonyms.length) return antonyms[r];
        r -= antonyms.length;
        if (r < hyponyms.length) return hyponyms[r];
        r -= hyponyms.length;
        if (r < hypernyms.length) return hypernyms[r];
        r -= hypernyms.length;
        return word;
    }
}

unittest
{
    import std.random;
    // known-good seed
    rndGen.seed(0);
    Word word = {
      word: "animal",
      synonyms: ["beast", "creature"],
      hypernyms: ["animate object", "thing"],
      hyponyms: ["mammal", "reptile"],
      antonyms: []
    };
    ulong[string] freq;
    foreach (w; word.synonyms ~ word.hyponyms ~ word.hypernyms ~ word.antonyms)
    {
        freq[w] = 0;
    }
    enum attempts = 10000;
    foreach (attempt; 0 .. attempts)
    {
        auto s = word.randomReplacement;
        assert(s in freq, "failed to find word [" ~ s ~ "] in freq table");
        freq[s]++;
    }
    foreach (k, v; freq)
    {
        import std.math;
        import std.format;
        auto diff = abs((v / cast(double)attempts) - (freq.length / cast(double)attempts));
        assert(diff < 0.2, format("word %s not properly represented: %s/%s for %s keys", k, v,
                    attempts, freq.length));
    }
}


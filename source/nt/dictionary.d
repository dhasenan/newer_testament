module nt.dictionary;

import d2sqlite3;
import std.typecons;
import std.string;

struct Word
{
    /// The word itself, forced into lowercase
    string word;
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
        static foreach (f; _listfields)
        {
            __traits(getMember, this, f) =
                (__traits(getMember, this, f) ~ __traits(getMember, other, f))
                    .sort
                    .uniq
                    .array;
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

class DB
{
    this(string filename)
    {
        _db = Database(filename);
        _db.run(`CREATE TABLE IF NOT EXISTS words
(
    word TEXT PRIMARY KEY,
    pronunciations TEXT,
    synonyms TEXT,
    antonyms TEXT,
    hyponyms TEXT,
    hypernyms TEXT
)`);
        _updater = _db.prepare(`
                UPDATE words
                SET pronunciations = :pronunciations,
                    synonyms = :synonyms,
                    antonyms = :antonyms,
                    hyponyms = :hyponyms,
                    hypernyms = :hypernyms
                WHERE word = :word`);
        _inserter = _db.prepare(`
                INSERT INTO words
                (word, pronunciations, synonyms, antonyms, hyponyms, hypernyms)
                VALUES
                (:word, :pronunciations, :synonyms, :antonyms, :hyponyms, :hypernyms)`);
        _fetcher = _db.prepare(`SELECT * FROM words WHERE word = :word`);
    }

    void cleanup()
    {
        _updater.finalize;
        _inserter.finalize;
        _fetcher.finalize;
        _db.close;
    }

    void beginTransaction()
    {
        _db.run("BEGIN TRANSACTION");
    }

    void commit()
    {
        _db.run("COMMIT TRANSACTION");
    }

    void save(Word word)
    {
        auto existing = get(word.word);
        auto op = _inserter;
        if (!existing.isNull)
        {
            word.merge(existing.get);
            op = _updater;
        }
        op.reset;
        op.bind(":word", word.word);
        static foreach (f; _listfields)
        {
            op.bind(":" ~ f, __traits(getMember, word, f).join(","));
        }
        op.execute;
    }

    Nullable!Word get(string w)
    {
        _fetcher.reset;
        _fetcher.bind(":word", w.toLower);
        auto results = _fetcher.execute;
        if (results.empty) return Nullable!Word.init;
        auto row = results.front;
        Word word;
        word.word = row["word"].as!string;
        static foreach (f; _listfields)
        {
            __traits(getMember, word, f) = row[f].as!string.split(",");
        }
        return nullable(word);
    }
    private:
    Database _db;
    Statement _updater, _fetcher, _inserter;
}

private enum _listfields = ["pronunciations", "synonyms", "antonyms", "hyponyms", "hypernyms"];

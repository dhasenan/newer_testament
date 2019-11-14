module nt.wiktionary;

import nt.books;
import nt.util;
import nt.dictionary;
import nt.db;

import dxml.parser;
import std.stdio;
import std.algorithm;
import std.experimental.logger;
import std.string;
import std.typecons;
import std.uni;

void importMain(string[] args)
{
    import std.getopt;
    string wik, mythes, dictionary;
    string database = "dict.sqlite3";
    auto opts = getopt(args,
            "w|wiktionary", "wiktionary input", &wik,
            "m|mythes", "MyThes input", &mythes,
            "u|dictionary", "path to word list", &dictionary,
            "d|database", "database location (created if necessary)", &database);
    if (opts.helpWanted)
    {
        defaultGetoptPrinter("import wiktionary data", opts.options);
        return;
    }

    if (wik)
        loadDataFromXml(wik, database);
    if (mythes)
        loadDataFromMyThes(mythes, database);
    if (dictionary)
        loadDataFromUsrShareDict(dictionary, database);
}

string replace(string input, string[string] replacements)
{
    string result;
    size_t end;
    foreach (word; input.toWords)
    {
        result ~= input[end .. word.start];
        end = word.end;
        if (auto p = word.word.toLower in replacements)
        {
            result ~= matchCase(word.word, *p);
        }
        else
        {
            result ~= word.word;
        }
    }
    result ~= input[end .. $];
    return result;
}

unittest
{
    auto replacements = [
        "apple": "pear",
        "box": "crate",
        "vacuum": "hoover",
    ];
    void test(string input, string expected)
    {
        string actual = replace(input, replacements);
        assert(actual == expected, format("expected: %s actual: %s", expected, actual));
    }

    test("Apple is the box.", "Pear is the crate.");
    test("Vacuum -- BOX.", "Hoover -- CRATE.");
    test("Apple is the box", "Pear is the crate");
}

void replaceSynonyms(DB db, Bible bible, double replacementRatio = 0.2)
{
    string[string] replacements;
    bool[string] stop = stopWords.dup;

    foreach (verse; bible.allVerses)
    {
        foreach (lex; verse.analyzed)
        {
            auto key = lex.word;
            if (key in stop) continue;
            if (auto p = key in replacements)
            {
                lex.word = *p;
                lex.variant = 0;
                continue;
            }
            import std.random : uniform;
            if (uniform(0.0, 1.0) >= replacementRatio)
            {
                stop[key] = true;
                continue;
            }
            // Try finding a replacement
            auto r = db.getWord(key);
            if (r is null)
            {
                tracef("failed to find in dictionary: " ~ key);
                stop[key] = true;
                continue;
            }
            auto newReplacement = r.randomReplacement;
            if (newReplacement.length == 0)
            {
                tracef("empty replacement for " ~ key);
                stop[key] = true;
                continue;
            }
            if (newReplacement == key)
            {
                tracef("self-replacement for %s", newReplacement);
                stop[key] = true;
                continue;
            }
            replacements[key] = newReplacement;
            lex.word = newReplacement;
        }
    }
}

bool[string] stopWords;

void loadDataFromMyThes(string mythesFilename, string dbFilename)
{
    auto db = new DB(dbFilename);
    db.beginTransaction;
    string term;
    Word word;
    word.word = term;
    ulong added = 0;
    foreach (line; File(mythesFilename).byLineCopy)
    {
        if (!line.startsWith("("))
        {
            if (word)
            {
                db.save(word);
                added++;
                if (added % 2000 == 0)
                {
                    db.commit;
                    db.beginTransaction;
                    tracef("added %s words from mythes", added);
                }
                word = null;
            }
            auto w = line.splitter("|").front.strip;
            if (!w.canFind!((dchar c) => c >= 0x80 || c == ' '))
            {
                // Skip non-ASCII stuff
                continue;
            }
            if (word.word in stopWords)
            {
                continue;
            }
            word.word = w.toLower;
            continue;
        }
        if (word is null) continue;
        foreach (w; line.splitter("|"))
        {
            auto a = w.indexOf(" (antonym)");
            if (a >= 0)
            {
                word.antonyms ~= w[0 .. a].strip;
                continue;
            }
            a = w.indexOf(" (similar term)");
            if (a >= 0)
            {
                word.synonyms ~= w[0 .. a].strip;
            }
            a = w.indexOf(" (related term)");
            if (a >= 0)
            {
                word.synonyms ~= w[0 .. a].strip;
            }
            a = w.indexOf(" (generic term)");
            if (a >= 0)
            {
                word.hypernyms ~= w[0 .. a].strip;
            }
            if (w.indexOf("(") < 0)
            {
                word.synonyms ~= w.strip;
            }
        }
    }
    if (word) db.save(word);
    db.commit;
    db.cleanup;
}

void loadDataFromXml(string xmlFilename, string dbFilename)
{
    auto db = new DB(dbFilename);
    scope (exit) db.cleanup;

    // I could use File.byLine.joiner or the like, but I didn't realize that before doing the mmap
    // thing. Oh well.
    auto text = mmap(xmlFilename);
    auto entities = parseXML!simpleXML(text);
    string lastTitle;
    db.beginTransaction;
    ulong added = 0;
    ulong found = 0;
    while (!entities.empty) with (EntityType)
    {
        auto e = entities.front;
        entities.popFront;
        if (e.type == elementStart && e.name == "title")
        {
            if (entities.front.type != text)
            {
                tracef("expected <title> to contain text at %s, but found %s", e.pos,
                        entities.front.type);
                continue;
            }
            lastTitle = entities.front.text;
            entities.popFront;
        }
        if (e.type == elementStart && e.name == "text")
        {
            if (entities.front.type != text)
            {
                tracef("expected <text> to contain text at %s, but found %s", e.pos,
                        entities.front.type);
                continue;
            }
            found++;
            if (found % 50_000 == 0)
            {
                tracef("found %s articles, of which %s were words; current title %s", found, added,
                        lastTitle);
            }
            if (addEntry(db, lastTitle, entities.front.text))
            {
                added++;
                if (added % 2_000 == 0)
                {
                    db.commit;
                    tracef("added entries from %s articles", added);
                    db.beginTransaction;
                }
            }
            entities.popFront;
        }
    }
    db.commit;
    tracef("finished after processing %s articles", added);
}

bool addEntry(DB db, string title, string article)
{
    if (!article.canFind("English")) return false;
    if (article.canFind("Proper Name")) return false;

    enum thesaurusStart = "Thesaurus:";
    enum engStartTag = "\n==English==\n";

    // Single-word entries only
    if (title.indexOf(" ") >= 0) return false;

    // No English version? Don't bother adding it
    auto s = article.indexOf(engStartTag);
    if (s < 0) return false;
    // Otherwise, fast-forward to the English version (we'll only take the first block)
    // TODO gather all definitions (the `===Etymology 1===` type sections)
    article = article[s .. $];

    if (title.startsWith(thesaurusStart))
    {
        addThesaurusEntry(db, title[thesaurusStart.length .. $].toLower, article);
        return true;
    }
    else if (title.indexOf(":") < 0)
    {
        addDefinition(db, title.toLower, article);
        return true;
    }
    return false;
}

private string findSection(string name)(string text)
{
    auto start = text.indexOf("=" ~ name ~ "=");
    if (start < 0) return "";
    text = text[start .. $];
    text = text[text.indexOf("\n") .. $];
    auto end = text.indexOf("===") - 1;
    if (end >= 0)
        text = text[0 .. end];
    return text;
}

private string[] findWords(string section)
{
    enum start = "{{ws|";
    enum start2 = "{{l|en|";
    enum end = "}}";
    string[] words;
    while (section.length)
    {
        auto s = section.indexOf(start);
        if (s >= 0)
        {
            section = section[s + start.length .. $];
        }
        else
        {
            s = section.indexOf(start2);
            if (s >= 0)
            {
                section = section[s + start2.length .. $];
            }
            else
            {
                break;
            }
        }
        s = section.indexOf(end);
        if (s < 0) break;
        auto d = section[0 .. s];
        auto earlyEnd = d.indexOf("|");
        if (earlyEnd >= 0) d = d[0..earlyEnd];
        words ~= d;
        section = section[s + end.length .. $];
    }
    return words;
}

void addThesaurusEntry(DB db, string title, string article)
{
    Word w;
    w.word = title;
    w.synonyms = article.findSection!"Synonyms".findWords;
    w.antonyms = article.findSection!"Antonyms".findWords;
    w.hyponyms = article.findSection!"Hyponyms".findWords;
    w.hypernyms = article.findSection!"Hypernyms".findWords;
    db.save(w);
}

void addDefinition(DB db, string title, string article)
{
    Word w;
    w.word = title;
    // Regular entries can have this too, I think, not just special thesaurus entries
    w.synonyms = article.findSection!"Synonyms".findWords;
    w.antonyms = article.findSection!"Antonyms".findWords;
    w.hyponyms = article.findSection!"Hyponyms".findWords;
    w.hypernyms = article.findSection!"Hypernyms".findWords;
    enum start = "{{IPA|en|/", end = "/}}";
    while (article.length)
    {
        auto s = article.indexOf(start);
        if (s < 0 || s + start.length >= article.length) break;
        article = article[s + start.length .. $];
        auto e = article.indexOf(end);
        if (e < 0) break;
        w.pronunciations ~= article[0 .. e];
        article = article[e + end.length .. $];
    }
    db.save(w);
}


void loadDataFromUsrShareDict(string dict, string dbPath)
{
    import std.range;
    auto db = new DB(dbPath);
    auto f = File(dict, "r");
    db.beginTransaction;
    foreach (i, line; f.byLine.enumerate)
    {
        line = line.strip;
        if (line.indexOf("'") >= 0) continue;
        if (line.indexOf(" ") >= 0) continue;
        // TODO save proper names to db so we can catch them more reliably
        if (line != line.toLower) continue;
        Word word;
        word.word = line.idup;
        db.save(word);
        if (i > 0 && i % 1000 == 0)
        {
            tracef("%s: imported %s words", dict, i);
        }
    }
    db.commit;
    db.cleanup;
}


static this() {
    // Taken from a public listing based on mysql's stopwords list for English
    // TODO pare this list down
    stopWords = [
        "a": true,
        "about": true,
        "above": true,
        "across": true,
        "after": true,
        "afterwards": true,
        "again": true,
        "against": true,
        "all": true,
        "almost": true,
        "alone": true,
        "along": true,
        "already": true,
        "also": true,
        "although": true,
        "always": true,
        "am": true,
        "among": true,
        "amongst": true,
        "amoungst": true,
        "amount": true,
        "an": true,
        "and": true,
        "another": true,
        "any": true,
        "anyhow": true,
        "anyone": true,
        "anything": true,
        "anyway": true,
        "anywhere": true,
        "are": true,
        "around": true,
        "as": true,
        "at": true,
        "back": true,
        "be": true,
        "became": true,
        "because": true,
        "become": true,
        "becomes": true,
        "becoming": true,
        "been": true,
        "before": true,
        "beforehand": true,
        "behind": true,
        "being": true,
        "below": true,
        "beside": true,
        "besides": true,
        "between": true,
        "beyond": true,
        "bill": true,
        "both": true,
        "bottom": true,
        "but": true,
        "by": true,
        "call": true,
        "can": true,
        "cannot": true,
        "cant": true,
        "co": true,
        "computer": true,
        "con": true,
        "could": true,
        "couldnt": true,
        "cry": true,
        "de": true,
        "describe": true,
        "detail": true,
        "do": true,
        "done": true,
        "down": true,
        "due": true,
        "during": true,
        "each": true,
        "eg": true,
        "eight": true,
        "either": true,
        "eleven": true,
        "else": true,
        "elsewhere": true,
        "empty": true,
        "enough": true,
        "etc": true,
        "even": true,
        "ever": true,
        "every": true,
        "everyone": true,
        "everything": true,
        "everywhere": true,
        "except": true,
        "few": true,
        "fifteen": true,
        "fify": true,
        "fill": true,
        "find": true,
        "fire": true,
        "first": true,
        "five": true,
        "for": true,
        "former": true,
        "formerly": true,
        "forty": true,
        "found": true,
        "four": true,
        "from": true,
        "front": true,
        "full": true,
        "further": true,
        "get": true,
        "give": true,
        "go": true,
        "had": true,
        "has": true,
        "hasnt": true,
        "have": true,
        "he": true,
        "hence": true,
        "her": true,
        "here": true,
        "hereafter": true,
        "hereby": true,
        "herein": true,
        "hereupon": true,
        "hers": true,
        "herself": true,
        "him": true,
        "himself": true,
        "his": true,
        "how": true,
        "however": true,
        "hundred": true,
        "i": true,
        "ie": true,
        "if": true,
        "in": true,
        "inc": true,
        "indeed": true,
        "interest": true,
        "into": true,
        "is": true,
        "it": true,
        "its": true,
        "itself": true,
        "keep": true,
        "last": true,
        "latter": true,
        "latterly": true,
        "least": true,
        "less": true,
        "ltd": true,
        "made": true,
        "many": true,
        "may": true,
        "me": true,
        "meanwhile": true,
        "might": true,
        "mill": true,
        "mine": true,
        "more": true,
        "moreover": true,
        "most": true,
        "mostly": true,
        "move": true,
        "much": true,
        "must": true,
        "my": true,
        "myself": true,
        "name": true,
        "namely": true,
        "neither": true,
        "never": true,
        "nevertheless": true,
        "next": true,
        "nine": true,
        "no": true,
        "nobody": true,
        "none": true,
        "noone": true,
        "nor": true,
        "not": true,
        "nothing": true,
        "now": true,
        "nowhere": true,
        "of": true,
        "off": true,
        "often": true,
        "on": true,
        "once": true,
        "one": true,
        "only": true,
        "onto": true,
        "or": true,
        "other": true,
        "others": true,
        "otherwise": true,
        "our": true,
        "ours": true,
        "ourselves": true,
        "out": true,
        "over": true,
        "own": true,
        "part": true,
        "per": true,
        "perhaps": true,
        "please": true,
        "put": true,
        "rather": true,
        "re": true,
        "same": true,
        "see": true,
        "seem": true,
        "seemed": true,
        "seeming": true,
        "seems": true,
        "serious": true,
        "several": true,
        "she": true,
        "should": true,
        "show": true,
        "side": true,
        "since": true,
        "sincere": true,
        "six": true,
        "sixty": true,
        "so": true,
        "some": true,
        "somehow": true,
        "someone": true,
        "something": true,
        "sometime": true,
        "sometimes": true,
        "somewhere": true,
        "still": true,
        "such": true,
        "system": true,
        "take": true,
        "ten": true,
        "than": true,
        "that": true,
        "the": true,
        "their": true,
        "them": true,
        "themselves": true,
        "then": true,
        "thence": true,
        "there": true,
        "thereafter": true,
        "thereby": true,
        "therefore": true,
        "therein": true,
        "thereupon": true,
        "these": true,
        "they": true,
        "thick": true,
        "thin": true,
        "third": true,
        "this": true,
        "those": true,
        "thou": true,
        "thee": true,
        "thy": true,
        "thine": true,
        "though": true,
        "three": true,
        "through": true,
        "throughout": true,
        "thru": true,
        "thus": true,
        "to": true,
        "together": true,
        "too": true,
        "top": true,
        "toward": true,
        "towards": true,
        "twelve": true,
        "twenty": true,
        "two": true,
        "un": true,
        "under": true,
        "until": true,
        "up": true,
        "upon": true,
        "us": true,
        "very": true,
        "via": true,
        "was": true,
        "we": true,
        "well": true,
        "were": true,
        "what": true,
        "whatever": true,
        "when": true,
        "whence": true,
        "whenever": true,
        "where": true,
        "whereafter": true,
        "whereas": true,
        "whereby": true,
        "wherein": true,
        "whereupon": true,
        "wherever": true,
        "whether": true,
        "which": true,
        "while": true,
        "whither": true,
        "who": true,
        "whoever": true,
        "whole": true,
        "whom": true,
        "whose": true,
        "why": true,
        "will": true,
        "with": true,
        "within": true,
        "without": true,
        "would": true,
        "ye": true,
        "yet": true,
        "you": true,
        "your": true,
        "yours": true,
        "yourself": true,
        "yourselves": true,
    ];
}


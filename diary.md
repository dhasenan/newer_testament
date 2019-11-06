# Devlog!

## Initial hack: by-verse

I tried training the markov chain by whole verse. This obviously sucked. A verse is just too much
state. I got the Bible, but starting at a random place.

## Second hack: by-word

I tried a word-by-word markov chain with 2, 3, and 4 word states. This was obviously bad, producing
output that was barely legible. Next I tried with a 4-5 word state.

## Third hack: topic detection

The third attempt is detecting important words in each verse. Then we train the Markov chain on
those important words. Finally, we inflate important words into verses simply by looking up a verse
with that important word.

An important word appears often enough to be a recurring theme, but otherwise is the least common
word in the verse.

I might need to blacklist certain things, eg names, if they're troublesome. Or I could add a
requirement that the thing appears in multiple books or in multiple chapters.

This didn't turn out super well, to be honest. I can almost kind of make sense of it?

## Fourth hack: name detection

A name is something that only appears capitalized. We should probably do a bit of stemming to figure
out related terms (eg Amalek matches Amalekiets). We're not going to figure out the difference
between place names and person names in this pass.

We want to whitelist a few names ("LORD", "Lord GOD", "Jesus", "Christ").

Anyway, we pick a number of proper nouns to include in a book, then figure out subsets to include in
each chapter. Right now I'm doing a couple of dials to see how many people to include. The base
number is the largest number of people in one verse.

## Fourth hack: synonyms

The Bible is great and all, but what every writer really needs is a good thesaurus. It can really
spice up your prose, you know?

There are two thesauruses worth considering: MyThes and Wiktionary. Wiktionary also includes
pronunciations, which will help out at a later step.

I extracted the data from Wiktionary and MyThes and dumped it into a sqlite database.

Unfortunately, these synonyms are only listed based on base words, not derived words. We need to
introduce a stemming algorithm to fix that. Also it includes multi-word replacements that require
some effort to work into the sentence, not just replacement (eg "I will vomit them out of my mouth"
gets turned into "I will throw up them out of my mouth"). Still, the basic structure works!

## Fifth hack: stemming and part-of-speech tagging

Prepositions are a fixed list:
https://en.wikipedia.org/wiki/List_of_English_prepositions

Each word has its own list of parts of speech. (I'd be better off using Esperanto, really...but
Esperanto doesn't have a massive lexicon like English, so fewer synonyms available. I'd have to go
with related terms. Probably triangulate from several other language thesauruses.)

To complicate matters, there's transitivity to consider for verbs.

D doesn't have good part-of-speech tagging libraries available. I'm going to use Spacy in Python to
break down individual verses into tagged documents. I can do this once on input and once on output.

This gives me better tools for working with the intermediate forms, instead of using the text and
manually splitting it and so forth.

### Moving the NLP analysis (and maybe more?) to initial ingestion

This is an efficiency thing. I'd rather not wait six whole minutes every time for the NLP to run
when I can just run it when I turn the raw text into JSON.

### Figure out name detection

Spacy is kinda crud with name detection. It seems to think "hath" is a proper noun. "Heaven" and
"God" are more understandable, but then there are things like "night". It identifies a total of 1007
lowercase words as proper nouns, which is frankly unusable (the Bible's only got like 33k words!).

The question is, does it miss anything? If not, that would be a decent first-pass filter.

### Switch to a newer translation

Spacy doesn't handle words like "shouldst" and "hath", and it's bad with things as simple as "ye".
The World English Bible is a public domain translation from the late 1990s, so it should use
language more amenable to Spacy parsing.

## Interlude: cleanup and tail-chasing

I noticed that the whole process was taking much longer than I liked and wanted to break it down
into narrower chunks, set up a build system, etc. I actually started writing a build system. I also
wanted a way to describe a production process from input file to epub in a handy fashion that I
could check into source control.

However, these are their own projects of decent size. I ended up breaking each discrete operation
into a separate step that I could run separately and didn't do anything fancy beyond that.

## Interlude: UTF8 errors

Something weird is happening with UTF8 encoding errors. When I pass a string through NLP, the string
seems to be mutated.

This doesn't happen with suitably short inputs, but with the whole of the WEB Bible, it does occur.
I'm trying to do more UTF8 validation so I at least get a replacement character, but I'm really not
sure where it's happening. It might be something about reused / mutable memory, so I'm adding some
duplication in a couple places defensively.

If this doesn't work out so well, I will switch to a full-Python version of NLP processing, which
should hopefully not suffer from these problems. That might also be a little faster? More IO, but
less interop memory copying.

I might also be able to use extensive logging to figure out where things are going wrong...but if
it's memory corruption, that's going to be an O(n²) operation where we check absolutely everything
against a clean copy of our input.

Testing...

Yep! Extra copies fixed the issue. Now I'm copying things over when I pass them to Python and again
when I receive them back from Python.




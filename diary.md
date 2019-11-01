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

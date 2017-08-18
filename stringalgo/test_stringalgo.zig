// -*- mode: zig; -*-

const io = @import("std").io;

const bitap = @import("bitap.zig");
const qs = @import("quicksearch.zig");

const levenshtein = @import("levenshtein.zig");
const wagnerfisher = levenshtein.wagnerfisher;

fn test_levenshtein(a: []const u8, b: []const u8) -> %void {
    const wfl = wagnerfisher(a, b);
    %%io.stdout.printf("'{}' <-> '{}' is {}\n", a, b, wfl);
}

fn test_all_levenshteins() {
    %%io.stdout.printf("*** Levenshtein tests ***\n");
    %%test_levenshtein("hello", "hallo");
    %%test_levenshtein("hell", "hallo");
    %%test_levenshtein("hell", "hello");
    %%test_levenshtein("help", "yelp");
    %%test_levenshtein("he", "hello");
    %%test_levenshtein("he", "h");
    %%test_levenshtein("rosettacode", "raisethysword");
    %%test_levenshtein("raisethysword", "rosettacode");
    %%test_levenshtein("drowsyhtesiar", "edocattesor");
    %%test_levenshtein("kitten", "sitting");
    %%test_levenshtein("kitten", "k_tt_n");
    %%test_levenshtein("aye", "bye");
    %%test_levenshtein("right", "high");
    %%test_levenshtein("zig", "zag");
    %%test_levenshtein("", "zag");
    %%test_levenshtein("zig", "");
    %%test_levenshtein("zig", "big");
    %%test_levenshtein("zigzag", "bigbag");
    %%test_levenshtein("the best of all", "all of the best");
    %%test_levenshtein("the best of all", "best of all");
    %%test_levenshtein("the best ever", "the next level");
    %%test_levenshtein("cult", "colt");
    %%test_levenshtein("pizza", "piazza");
    %%test_levenshtein("mosquito", "mojito");
    %%test_levenshtein("dårlig vær", "dårlig klær");
    %%test_levenshtein("", "");
}

fn test_bitap_quicksearch(text: []const u8, pattern: []const u8) {
    var bix: isize = 0;
    var qix: isize = 0;
    // handle error?
    bix = %%bitap.bitap_search(text, pattern);
    qix = qs.quicksearch(pattern, pattern.len, text, text.len);
    %%io.stdout.printf("'{}' bitap {} (qs {})", pattern, bix, qix);
    if (bix > -1) {
        // how can printf give us a 'character'?
        %%io.stdout.printf(" -> '{}/", text[usize(bix)]);
        %%io.stdout.writeByte(text[usize(bix)]);
        %%io.stdout.printf("', found\n");
    } else {
        %%io.stdout.printf(", not found\n");
    }
}

fn test_all_bitaps() {
    //            0         1         2         3
    //            0123456789012345678901234567890123456789
    const text = "this is the text that we will look at\x00"; // need the 0 termination
    %%io.stdout.write("*** bitap/quicksearch tests ***\n");
    %%io.stdout.write("             0123456789012345678901234567890123456789\n");
    %%io.stdout.printf("Looking in: '{}'\n", text);
    test_bitap_quicksearch(text, "will");
    test_bitap_quicksearch(text, "wall");
    test_bitap_quicksearch(text, "some");
    test_bitap_quicksearch(text, "at");
    test_bitap_quicksearch(text, " at");
    test_bitap_quicksearch(text, "looked");
    test_bitap_quicksearch(text, "look");
    test_bitap_quicksearch(text, "l l");
    test_bitap_quicksearch(text, "t t");
    test_bitap_quicksearch(text, "");
}

pub fn main() -> %void {
    test_all_levenshteins();
    test_all_bitaps();
}

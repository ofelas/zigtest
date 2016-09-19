// -*- mode: zig; -*-

const io = @import("std").io;

const bitap = @import("bitap.zig");
const qs = @import("quicksearch.zig");

const levenshtein = @import("levenshtein.zig");
const wagnerfisher = levenshtein.wagnerfisher;

fn test_levenshtein(a: []u8, b: []u8) -> %void {
    var wfl: usize = 0;
    wfl = wagnerfisher(a, b);
    %%io.stdout.write("'");
    %%io.stdout.write(a);
    %%io.stdout.write("' <-> '");
    %%io.stdout.write(b);
    %%io.stdout.write("' is ");
    %%io.stdout.printInt(usize, wfl);
    %%io.stdout.printf("\n");
}

fn heading(text: []u8) {
    %%io.stdout.write("*** ");
    %%io.stdout.write(text);
    %%io.stdout.printf(" ***\n");
}

fn test_all_levenshteins() {
    heading("Levenshtein tests");
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

fn test_bitap_quicksearch(text: []u8, pattern: []u8) {
    var bix: isize = 0;
    var qix: isize = 0;
    bix = %%bitap.bitap_search(text, pattern);
    qix = qs.quicksearch(pattern, pattern.len, text, text.len);
    %%io.stdout.write("'");
    %%io.stdout.write(pattern);
    %%io.stdout.write("' bitap ");
    %%io.stdout.printInt(isize, bix);
    %%io.stdout.write(" (qs ");
    %%io.stdout.printInt(isize, qix);
    %%io.stdout.write(")");
    if (bix > -1) {
        %%io.stdout.write(" -> '");
        %%io.stdout.writeByte(text[usize(bix)]);
        %%io.stdout.write("'");
        %%io.stdout.printf(", found\n");
    } else {
        %%io.stdout.printf(", not found\n");
    }
}

fn test_all_bitaps() {
    //            0         1         2         3
    //            0123456789012345678901234567890123456789
    const text = "this is some text that we will looked at\x00"; // need the 0 termination
    heading("bitap/quicksearch tests");
    %%io.stdout.write("Looking in: '");
    %%io.stdout.write(text);
    %%io.stdout.printf("'\n");
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

pub fn main(args: [][]u8) -> %void {
    test_all_levenshteins();
    test_all_bitaps();
}

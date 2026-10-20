# JSONTestSuite fixtures

Unmodified copy of `test_parsing/` from [nst/JSONTestSuite](https://github.com/nst/JSONTestSuite)
(MIT, see `LICENSE`), the 318 files of the repository's default branch at the time of copying
(2026-10-20). `MANIFEST.txt` lists them in byte order so the suite needs no directory listing.
Files are binary (`.gitattributes` `-text`): several contain invalid UTF-8, CRLF or a byte order mark.

`y_` files must decode, `n_` files must be rejected, `i_` files may go either way.
The suite is `tests/suites/corpus.lua`.

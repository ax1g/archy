-- Screencopy settings.
--
-- allow_token_by_default lets grim, slurp and the recording pipeline read the
-- compositor output without an interactive auth prompt on every capture, which
-- is what a screenshot key has to be. Without it the first grim call per
-- session blocks on a permission dialog nobody is there to answer.

hl.config({
  screencopy = {
    allow_token_by_default = true,
  },
})

# Event Contract

`PresentationEvent` is the only cross-module runtime message. Producers must use a matching `kind` and `payload` pair. Consumers should ignore kinds they do not understand so a newer producer can work with an older UI during development.

All timestamps are milliseconds from the start of the presentation session. Event IDs and candidate IDs are UUIDs. JSONL files contain one encoded `PresentationEvent` per line.

The UI consumes `judgeReaction`; it does not render `ruleCommentCandidate` or `llmCommentCandidate` directly. The feedback director is responsible for turning candidates into reactions.

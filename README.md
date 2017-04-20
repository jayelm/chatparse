# Chatparse

This is a Ruby script designed to parse and convert files in the [CHAT
Transcription format](http://childes.talkbank.org/manuals/CHAT.pdf) of natural
language conversations, most commonly used in the CHILDES (Child Language Data
Exchange System) corpus at CMU (http://childes.psy.cmu.edu/).

Currently `chatparse` can convert from `.cha` to `.yaml` and back.

## Usage

```
$ ruby chatparse.rb transcript.cha  # Makes transcript.yaml
```

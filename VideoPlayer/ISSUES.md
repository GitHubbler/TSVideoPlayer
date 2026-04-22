# ISSUES

1. Each voice command seems to be executed more than once.
* What exactly happens with voice after the first command now?
    * Stops entirely? NO (not sure, ignores commands, don't know if it is temporarily ignoring or stopped entirely.)
    * Keeps transcribing but no callbacks fire? Shows transcript on screen intermittently--does not necessarily execute what is presented.
    * Repeats commands? YES, but only if it has decided to execute the command at all, and sometimes does not repeat.

* Any console output from Speech / AVAudioEngine when it fails
after several commands, only these two lines in the console:
<<<< FigFilePlayer >>>> signalled err=-12860 at <>:37512
<<<< FigFilePlayer >>>> signalled err=-12860 at <>:37512


2. The last file played is not re-opened (not loaded at all) on re-launch. This was a feature which was (attempted to be) added in the previous commit.

* Whether the persistence issue is now:
    * Not loading YES
    * Loading but not playing NO
    * Failing only on iOS vs macOS
only tested on macOS (initial target)

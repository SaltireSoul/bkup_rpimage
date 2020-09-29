 # Changelog 

# v1.3 - slmingol

- `Heredoc` (`cat << EOF`) instead of `echo -e` for better legibility. [Changes originally made by **slmingol**, in a fork from the original project](https://github.com/slmingol/bkup_rpimage)

# v1.2 - lzkelley

[Original project on Github by **lzkelley**](https://github.com/lzkelley/bkup_rpimage), latest modification on `2019-05-08`, with these changes specified in the bkup_rpimage.sh file:

- `2019-04-25` **Dolorosus:**
    - fix: Proper quoting of imagename. Now blanks in the imagename should be no longer a problem.

- `2019-03-19` **Dolorosus**:
    - fix: Define colors only if connected to a terminal
        Thus output to file is no more cluttered.

- `2019-03-18` **Dolorosus**:
      - add: exclusion of files below /tmp,/proc,/run,/sys and also the swapfile /var/swap will be excluded from backup.
      - add: Bumping the version to 1.1

- `2019-03-17` **Dolorosus:**
    - add: -s parameter to create an image of a   defined size.
    - add: funtion cloneid to clone te UUID and the PTID from the SDCARD to the image. So restore is working on recent raspian versions.

# v1.0 - jinx

- `2014-11-10` bkup_rpimage.sh v1.0 by **jinx** at the [Raspberry Pi Forum](https://www.raspberrypi.org/forums/viewtopic.php?p=638345#p638345)



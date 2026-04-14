## CHANGELOG

### v2.1.0
MCM Integration added
Added the ability to automatically load a round to the chamber with Shift + R. The same Shift+R removes the bullet again (If you do this with a loaded magazine the gun won't shoot keep in mind)
fixed bug that it was not longer possible to clear chamber manually when a mag is attached to the weapon.
Set the timer for the duration of the item lock of an active weapon to the animation_length.

### 2.0.3
improved overall code structure
bugfix calling close() while being in the inventory while putting a round into the chamber no longer causes a softlock
bugfix while chambering a round and closing the inventory right after, the chamber process wont get cancelled and loads the chamber correctly

### v2.0.2
fixed an ammo duplication bug when inserting a loaded magazin to a weapon that has an empty chamber

### v2.0.1
bugfix correct weaponstate after clearing the chamber
bugfix mod handling active weapons with attached magazins now correctly

### v2.0.0
added the already existing animations to clearing the chamber and chambering rounds on active weapons.

### v1.3.0
added a charge sound after loading the round into the chamber or clearing the chamber
added weaponstate check so if the chamber is cleared of an active weapon the weapon state is set accordingly to weapon empty.

### v1.2.0
fixed folder naming

### v1.1.3
Excluded manual loaded weapons like Mosin or Remington

### v1.1.2
added a timer to chambering a round. it is the same timer when clearing the chamber

### v1.1.1
Bugfix Animation of removing the magazine now plays properly when removing the mag from the gun and a round is still chambered

### v1.1.0
Changed the sound to AmmoLoad, when chambering round
Added the ability to clear the chamber when the weapon is equipped

### v1.0.0
initial main release
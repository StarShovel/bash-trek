#!/bin/bash

# Bash Trek – a Bash implementation of the classic Star Trek terminal game
# Copyright (C) 2025 James Gibbon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Version 1.0 - October 2025
# Requires Bash >= 4.3

qdistance () {

 ## max possible is 9
 # x1 y1 x2 y2

 local -i d1=$(( $1 - $3 ))
 local -i d2=$(( $2 - $4 ))
 local -n dist=$5

 # absolute values
 local -i absd1=${d1#-}
 local -i absd2=${d2#-}

 # fake euclidean
 if (( absd1 < absd2 )); then
    (( dist = absd2 + (absd1 + 2) / 4 ))
 else
    (( dist = absd1 + (absd2 + 2) / 4 ))
 fi
}

coordsetup () {
 # all globals
 (( quadx = (entx >> 3), quady = (enty >> 3 ) ))
 (( qindex = (quady << 3) + quadx ))
 (( localx = (entx & 7), localy = (enty & 7) ))
 (( entind = (localy << 3) + localx ))
}

wormtravel () {

 local -i qind qy ybase r
 local -n newx=$1 newy=$2

 (( r = RANDOM ))
 newx=$(( r & 63 ))
 newy=$(( (r >> 6) & 63 ))

 # walk through the X until we find "unoccupied"
 # only 5 quads can be cached at any time
 (( qy = newy >> 3 ))
 (( ybase = qy << 3 ))
 (( qind = ybase + (newx >> 3) ))

 while [[ -v objlist[$qind] ]]; do
    # just walk along the x path
    (( newx = (newx + 8) & 63 ))
    (( qind = ybase + (newx >> 3) ))
 done

}

wormhole () {
 # start up or close a wormhole?
 if [[ -v wormgo[qindex] ]]; then
    if (( wormgo[qindex] == 1 && (RANDOM % 3) == 1 && quadcnt > 3 )); then
       holeappear
       (( wormgo[qindex] = 2 )) # ready to vanish
    elif (( wormgo[qindex] > 1 )); then
       if (( ++wormgo[qindex] > 5 && (RANDOM % 3) == 1 )); then
          holeplace=
          if [[ $view == SRS ]]; then
             local dotpr=
             srsbuf dotpr $wormx $wormy "${dim} · ${off}"
             printf "$dotpr"
          fi
          mesg "wormhole at $wormx,$wormy collapsed"    
          unset lquad[wormind] wormgo[qindex]
       fi
    fi
 fi
}

garbagecollect () {
 local v
 local -i x i di

 (( x = stardate ))
 for i in ${!quadvisit[@]} ; do
    (( quadvisit[i] < x )) && (( di = i, x = quadvisit[i] ))
 done

 for v in basecache starcache objlist klicache scangrids quadvisit ; do
    unset "${v}[di]" 
 done
}

strikedamage() {
 local -n dam=$3
 # energy, distance
 (( dam = $1 / ($2 + 1) ))
}

delklingon () {
 local -i last idx=$1 lkind=$2 # indexes into klingon array and local quad
 local -i x=${klix[idx]} y=${kliy[idx]}
 local lkpat
 local dotpr=
 # note - view will be SRS
 srsbuf dotpr $x $y "${dim} · ${off}"
 printf "$dotpr"
 unset glsrsbuf gllrsbuf glmapbuf
 (( last = quadkli - 1 ))
 (( klix[idx]=klix[last], kliy[idx]=kliy[last], kshi[idx]=kshi[last] ))

 unset klix[last] kliy[last] kshi[last] lquad[lkind]

 # globals
 (( quadkli--, galkli-- ))
 (( galaxy[qindex]-=100 ))

 printf -v lkpat %02d "$lkind"
 klicache[qindex]=${klicache[qindex]/ $lkpat/}
 objlist[qindex]=${objlist[qindex]/ $lkpat/}
 
 statscreen -ck
 mesg "klingon at $x,$y destroyed"
}

maxbound() {
 local -i pos=$1 step=$2
 local -n mb=$3
 (( mb = step > 0 ? 63 - pos : step < 0 ? pos : 63 ))
}

maxtrav() {
 local -i x=$1 y=$2 vect=$3
 local -n  mt=$4
 local -i xstep=${xmult[$vect]} ystep=${ymult[$vect]}

 local -i xmax ymax

 maxbound $x $xstep xmax
 maxbound $y $ystep ymax

 (( mt = xmax < ymax ? xmax : ymax ))
}

replenish () {
 (( energy=1500, shields=900, torps=8 ))
}

resign () {
 mesg "resignation accepted"
 gameover="res"
}

getnum () {
 local prompt=$1 inmax=$2
 local -n rslt=$3
 local ncol newnum k innum=
 if [[ -v objf ]]; then
    ncol=$yel
    unset objf
 else
    ncol=
 fi
 
 printf "%s%s %s[0-%s]%s : " "$curnorm" "$prompt" "$ncol" "$inmax" "$off"
 while (( ${#innum} < 1 )) || [[ $k != "" ]] ; do
    read -rsn1 k
     if [[ $k == $'\x7f' ]]; then
       if (( ${#innum} > 0 )); then
          innum=${innum::-1}
          printf '\b \b'
       fi
    elif [[ $k =~ ^[0-9]$ ]] && [[ $innum != "0" ]]; then
       newnum=${innum}${k}
       if ! (( 10#$newnum > inmax )); then
          innum=$newnum
          printf $k
       fi
    fi
 done

 printf "\r\033[2K\r$curoff"
 rslt=$((10#$innum))
}

mesg () {
 printf "%s%s" "$msgpos" "$1"
 sleep 1
 printf "\r%s%s" "$dim" "$1"
 sleep 0.3
 printf "\r\033[2K\r$off"
 sleep 0.3
}

srsbuf () {
 local -n pbuf=$1
 local -i sx=$2 sy=$3
 local obj=$4

 printf -v pbuf '%s\033[%d;%dH%s' "$pbuf" $((bottom + sy - 19)) $((sx * 4 + 1)) "$obj"
}

shieldadjust () {
 local -i newsval
 getnum "new shield value" $((energy + shields)) newsval
 local -i incv=$((newsval - shields))
 shields=$newsval
 (( energy-=incv ))
 statscreen -ces
}
    
phaserfire () {

 if ! [[ $view == SRS ]]; then
    shortrangescan lquad
    printf $cmdpos
 fi

 if (( energy == 0 )); then
    mesg "insufficient weapon energy"
 elif (( docked )); then
    mesg "weapon operation not possible while docked"
 else
    local -i phaval strike
    getnum "phaser energy" $energy phaval
    (( energy -= phaval ))
    statscreen -ce

    if (( galaxy[qindex] > 99 )); then
       local -i qd
       #### runs backwards because delklingon can change kshi etc
       for (( i=quadkli-1; i>=0; i-- )); do
          qdistance ${klix[i]} ${kliy[i]} $localx $localy qd 
          strikedamage $((phaval + 200)) $qd strike
          (( kshi[i]-=strike ))
          if (( kshi[i] < 0 )); then
             delklingon $i $(( (kliy[i] << 3) + klix[i] ))
          else
             mesg "$strike unit hit on klingon at ${klix[i]},${kliy[i]}"
          fi
       done
    elif (( galaxy[qindex] % 100 > 9 )); then
       mesg "phaser energy deflected by starbase"
    else
       mesg "expended phaser energy into empty space"
    fi
 fi

}

cmd () {

 printf "%s%scommand " "$curnorm" "$cmdpos"
 local incmd= k=
 local newcmd
 
 local -n rslt=$1
 local availcmds=$2
 
  while (( ${#incmd} < 3 )) || [[ $k != $'\0' ]]; do
 
    read -rsn1 k
    if [[ $k == $'\x7f' ]]; then
       # backspace
       if (( ${#incmd} > 0 )); then
          incmd=${incmd::-1}
          printf '\b \b'
       fi   
    else   
       # convert to upper case
       newcmd=${incmd}${k^^}
       if [[ $availcmds == *-"$newcmd"* ]]; then
          incmd=$newcmd
          (( ${#incmd} < 4 )) && echo -n ${k^^}
       fi 
    fi
    
 done
  
 printf "%s" "$curoff"
 printf "\r\033[2K\r" #clear line and go to beginning
 rslt=$incmd

}

galaxymap () {
 
 # note - can't be called if map is already active
 # the command parser doesn't permit it

 if [[ -v glmapbuf ]]; then
    printf "%b" "$glmapbuf"
 else
    local gmbuf="$toppos"
    local rbuf
    local -i ybas x y

    for y in {0..7}; do
       rbuf=
       (( ybas = y << 3 ))
       for x in {0..7}; do
          if [[ -v seen[ybas+x] ]]; then
             (( x == quadx && y == quady )) && rbuf+="$cya"
             printf -v rbuf '%s %03d%s' "$rbuf" "${galaxy[ybas+x]}" "$off"
          else
             rbuf+=" ${dim}###${off}"
          fi
       done
       gmbuf+="$rbuf\n"
    done
    printf "%b" "$gmbuf"
    glmapbuf=$gmbuf
 fi

 view=MAP
}

klingonresponse () {

 if (( quadkli )); then

    local -i kenergy fdmg fx fy dmg i j tmp dice qd

    ## shuffle the klingons - for random firing order
    for ((i=quadkli-1; i>0; i--)); do
       (( j = RANDOM % (i+1) ))
       (( tmp=kshi[i], kshi[i]=kshi[j], kshi[j]=tmp ))
       (( tmp=klix[i], klix[i]=klix[j], klix[j]=tmp ))
       (( tmp=kliy[i], kliy[i]=kliy[j], kliy[j]=tmp ))
    done

    ((dice = RANDOM & 7 ))
    ## if 1 AND energy+shields!=0, one klingon doesn't fire
    ## if 2 OR energy+shields=0, one of them fires again

    ## loop through extant klingons in the quad
    for (( i=0; i<quadkli; i++ )); do
       # notional klingon energy reserve
       (( kenergy=kshi[i]+75 ))
       qdistance $localx $localy ${klix[i]} ${kliy[i]} qd
       strikedamage $kenergy $qd dmg

       # the last klingon can withhold fire randomly - but not if  en + shi = 0
       if (( i == quadkli - 1 && dice == 2 && shields + energy != 0 )); then
          mesg "no incoming fire from klingon at ${klix[i]},${kliy[i]}"
       else
          mesg "$dmg units damage from klingon at ${klix[i]},${kliy[i]}"
          (( shields-=dmg ))
       fi

       # cache the first strike
       (( i == 0 )) && (( fdmg=dmg, fx=klix[i], fy=kliy[i] ))
       
       statscreen -s
    done

    # ok to have a random second go only if it doesn't zero the energy.
    # imperative to, if energy is 0.
    if (( ( dice == 1 && shields + energy - fdmg != 0 ) || shields + energy == 0 )); then
       mesg "second $fdmg unit strike from klingon at $fx,$fy"
       (( shields-=fdmg ))
       statscreen -s
    fi   

    if ((shields < 0)); then
       # enterprise destroyed!
       mesg "warp core breach"
       gameover="des"
    fi
 fi

}

isdocked() {

 if (( galaxy[qindex] % 100 > 9 )); then
    local -i xdiff ydiff

    (( xdiff = localx - sbsx ))
    (( ydiff = localy - sbsy ))

    (( ${xdiff#-} < 2 && ${ydiff#-} < 2 )) && return 0
 fi

 return 1

}

banner() {

  sleep 1.5
  local bmesg="$1"
  local buf blank msgline top game bot pad
  local mstatus
  [[ $gameover = win ]] && mstatus="MISSION ACCOMPLISHED" || mstatus="   MISSION FAILED   "
  printf -v pad '%*s' 11 ''

  printf -v blank   ' │%*s│\n' 47 ''
  printf -v msgline ' │%-*s│\n' 47 "$pad$bmesg"
  printf -v top     ' ┌───────────────────────────────────────────────┐\n'
  printf -v game    " │             $mstatus              │\n"
  printf -v bot     ' └───────────────────────────────────────────────┘\n'

  buf="$toppos$top$blank$msgline$blank$blank$game$blank$bot"

  printf '%s' "$buf"

}

longrangescan () {

 if [[ -v gllrsbuf ]]; then
    printf "%b" "$gllrsbuf"
 else    
    local -i tmpind px py xc yc
    local rbuf temp
    local gllrsbuf="$toppos"
   
    rbuf="        "
   
    for px in {-1..1} ; do
       xc=$(( quadx + px ))
       if inrange 7 $xc; then
          rbuf+=" $xc      "
       else
          rbuf+=" -      "
       fi
    done
   
    gllrsbuf+="$rbuf\n"
    
    gllrsbuf+="     ┌───────┬───────┬───────┐  \n"
   
    for py in -1 0 1 ; do
       rbuf=
       (( yc = quady + py ))
       if inrange 7 $yc; then
          rbuf+="   "$yc" │"
          for px in -1 0 1 ; do
             (( xc = quadx + px ))
             if inrange 7 $xc; then
                (( tmpind = (yc << 3) + xc ))
                # mark seen
                if [[ ! -v seen[tmpind] ]]; then
                   (( seen[tmpind] = 1 ))
                   unset glmapbuf
                fi
                if (( galaxy[tmpind] > 99 )); then
                   rbuf+=${red}
                elif (( galaxy[tmpind] > 9 )); then
                   rbuf+=${cya}
                fi
                printf -v temp "  %03d${off}  │" ${galaxy[tmpind]}
                rbuf+=$temp
             else
                rbuf+="   ${dim}▫${off}   │"
             fi
          done
       else
          rbuf+="   - │   ${dim}▫${off}   │   ${dim}▫${off}   │   ${dim}▫${off}   │"
       fi
       gllrsbuf+="${rbuf}  \n"
       if (( py == 1 )); then
          gllrsbuf+="     └───────┴───────┴───────┘  \n"
       else
          gllrsbuf+="     ├───────┼───────┼───────┤  \n"
       fi
    done
    printf "%b" "$gllrsbuf"
 fi
 view=LRS

}

drawlabels () {

  printf "%s" "$toppos"
  printf $'\e[35Gquadrant\n\e[35Gcondition\n\n'
  printf $'\e[35Gstardate\n'
  printf $'\e[35Genergy\n\e[35Gklingons\n'
  printf $'\e[35Gshields\n\e[35Gtorpedoes\n'
  
}

statscreen () {

 local OPTIND=1
 local statbuf sdisp cond cclr opt s

 while getopts "qcdekst" opt; do
    case $opt in

      q) printf -v statbuf "${statb[20]}%6s" "$quadx,$quady" ;;

      c) if (( docked )); then
            cond="DOCKED"
            cclr=$cya
         elif (( quadkli )); then
            cond="RED"
            cclr=$red
         elif (( shields < 500 || energy < 600 )); then
            cond="AMBER"
            cclr=$yel
         else
            cond="GREEN"
            cclr=$grn
         fi
         printf -v statbuf "${statbuf}${statb[19]}%s%6s%s" $cclr $cond $off ;;

      d) s="${stardate%?}"
         printf -v statbuf "${statbuf}${statb[17]}%6s" ${s:0:-1}.${s: -1} ;;

      e) printf -v statbuf "${statbuf}${statb[16]}%6d" $energy ;;

      k) printf -v statbuf "${statbuf}${statb[15]}%6d" $galkli ;;

      s) (( shields < 0 )) && sdisp="DOWN" || sdisp=$shields
         printf -v statbuf "${statbuf}${statb[14]}%6s" $sdisp ;;

      t) printf -v statbuf "${statbuf}${statb[13]}%6d" $torps

    esac
 done

 printf "$statbuf"

}

holeanim () {

 local -i spos ba x y i
 local hdisplay

 for i in {0..3}; do
    hdisplay="$gridcanvas"
 
    for ba in 0 24 48 ; do
      (( spos = (RANDOM % 16) + ba ))
      (( x = spos % 8, y = spos / 8 ))
      srsbuf hdisplay $x $y " *"
    done
    printf "%b" "$hdisplay"
    sleep 0.2
 done

}

blankgrid () {

 local -i y
 gridcanvas="${toppos}${dim}" 
 for y in {0..7}; do
    gridcanvas+=" ·   ·   ·   ·   ·   ·   ·   ·  \n"
 done
 gridcanvas+=${off}

}

shortrangescan () {

 # only if unset (global)
 if [[ ! -v entplace ]]; then
    entplace=
    srsbuf entplace $localx $localy ${cya}-E-${off}
 fi

 view=SRS

 if [[ ! -v glsrsbuf ]]; then

    if [[ -v scangrids[qindex] ]]; then
       glsrsbuf=${scangrids[qindex]}
    else
       (( seen[qindex] = 1 ))
       local -n srsquad=$1
       local -i y x ybase

       local srsrow
       glsrsbuf=
       for y in {0..7}; do
          (( ybase = y << 3 ))
          srsrow=
          for x in {0..7}; do
             if ! [[ -v srsquad[ybase+x] ]]; then
                srsrow+=" ·  "
             else
                case ${srsquad[ybase+x]} in
                  1) srsrow+="${off} *  ${dim}" ;;
                  3) srsrow+="${off}${yel}>K< ${off}${dim}" ;;
                  2) srsrow+="${off}<B> ${dim}" ;;
                  5) srsrow+=" ·  " # will get overwritten initially by $holeplace
                esac
             fi
          done
          glsrsbuf+="$srsrow\n"
       done
       (( quadkli )) || scangrids[qindex]=$glsrsbuf

    fi
 fi

 printf "%b" "${toppos}${dim}${glsrsbuf}${off}${entplace}${holeplace}"

}

holeappear () {

 # find a grid position and insert a wormhole
 wormind=$(( RANDOM % 64 )) # global
  
 while (( wormind == entind )) || [[ -v lquad[wormind] ]]; do
    (( wormind = (wormind + 3) % 64 ))
 done

 (( lquad[wormind]=5 ))
 (( wormx = wormind % 8, wormy = wormind / 8 )) # globals

 holeplace=
 srsbuf holeplace $wormx $wormy " ○  "
 [[ $view == SRS ]] && printf "$holeplace"
 mesg "wormhole appeared at $wormx,$wormy"

}

objectsplace () {
  local -i opos adj diff i
  local -i qi=$1
  local -n  ocache=$2 olist=$5
  local -i onum=$3 otype=$4
  local pr ob

    ocache[qi]=
    for (( i=1; i<=onum; i++ )); do
       (( opos = RANDOM % 64 ))
       while : ; do
          (( adj = 0 )) # assume valid by default
             # test for adjacency
             for ob in ${olist[qi]} $entind ; do
                ob=$((10#$ob))
                (( diff = ob - opos ))
                (( diff < 0 )) && (( diff = -diff ))
                if (( diff < 2 || diff == 7 || diff == 8 || diff == 9 )); then
                   (( adj = 1 )) # no go
                   break
                fi
             done
          (( adj == 0 )) && break
          (( opos = (opos + 3) % 64 ))
       done
       printf -v pr '%02d' $opos
       ocache[qi]+=" $pr"
       olist[qi]+=" $pr"
    done

}

quadpop () {

 local -n fquad=$1 locquad=$2
 local ei
 fquad=()

 (( quadcnt = 0 )) # global

 # mark date of visit
 (( quadvisit[qindex] = stardate )) 

 (( quadkli = locquad[qindex] / 100 )) # global

 if [[ ! -v starcache[qindex] ]] || {
      printf -v ei '%02d' $entind
      [[ ${objlist[qindex]} == *" $ei"* ]]
 }; then # populate cache arrays

    local -i tmp j tmpi i
    local -i p

    # possible previously set, pre-collision
    unset scangrids[qindex]

    # inject the stars and klingons (if any)
    # entind is the 'linear' enterprise position in local quad
    # - it's a global.

    #stars
    objlist[qindex]=
    objectsplace $qindex starcache $(( locquad[qindex] % 10 )) 1 objlist

    # klingons
    if (( quadkli )); then
       objectsplace $qindex klicache $quadkli 3 objlist
    # base
    elif (( locquad[qindex] % 100 > 9 )); then
       objectsplace $qindex basecache 1 2 objlist
    fi

 fi

 for spos in ${starcache[qindex]// 0/ }; do
    (( fquad[spos] = 1 ))
 done

 if (( quadkli )); then
    local -i kpos kcnt=0
    for kpos in ${klicache[qindex]// 0/ }; do
       (( fquad[kpos] = 3 ))
       (( klix[kcnt] = kpos & 7, kliy[kcnt] = kpos >> 3, kshi[kcnt++] = 330 ))
    done
 elif [[ -v basecache[qindex] ]]; then
    local -i bpos
    bpos=${basecache[qindex]// 0/}
    (( fquad[bpos] = 2 ))
    (( sbsx = bpos & 7, sbsy = bpos >> 3 ))
 fi

}

inrange () {
 local -i max=$1 i
 shift
 for i in $* ; do
    (( i > max || i < 0 )) && return 1
 done
 return 0
}

quadmax () {

 local -i vect=$1 idx
 local -n quad=$2 max=$5
 local -i qx=$3 qy=$4 distcnt=0
   
 while : ; do
    (( qx+=xmult[vect], qy+=ymult[vect] ))
    if ! inrange 7 $qx $qy; then
       (( max = 63 ))
       break
    else
       (( idx = (qy << 3) + qx ))
       if  [[ -v quad[idx] ]]; then
          (( quad[idx] == 5 )) && (( distcnt++ )) # wormhole
          (( max = distcnt ))
          break
       fi
    fi
    (( distcnt += 1 ))
 done

}

navigate () {

 if (( energy > 0 )); then

    local -i xincr yincr dist vector maxdist objdist
    local -i newquad=0
    local -i destx desty

    getnum "direction" 7 vector
    quadmax $vector lquad $localx $localy objdist 

    maxtrav $entx $enty $vector maxdist
    (( objdist < maxdist )) && (( maxdist = objdist ))
    
    if (( maxdist == 0 )); then
       mesg "navigation constrained by object or galaxy edge"
    else
       local movestr=
       (( objdist < 63 )) && (( objf = 1 )) # flag for prompt colour
       getnum "warp" $(( energy < maxdist ? energy : maxdist )) dist
       local -i xincr=${xmult[$vector]}
       local -i yincr=${ymult[$vector]}
   
       # calculate destination - we jump there if we leave the local quad
       # note - since getnum is constrained, it must be legit
       (( destx=dist*xincr+entx, desty=dist*yincr+enty ))
       (( origx=localx, origy=localy ))
       (( energy-=dist ))
   
       while (( dist > 0 )) ; do
          (( entx+=xincr, enty+=yincr, dist-- ))
          (( localx+=xincr, localy+=yincr ))

          if inrange 7 $localx $localy; then

             # if set, then not empty space
             (( tmpidx = (localy << 3) + localx ))
             if  [[ -v lquad[tmpidx] ]]; then # can only be a wormhole
                wormtravel destx desty # get random, unoccupied entx & enty
                (( newquad = 1 )) # wormholed outside local quad
                (( energy+=dist ))
                if [[ $view == SRS ]]; then
                   local dotpr=
                   srsbuf dotpr $origx $origy "${dim} · ${off}"
                   srsbuf dotpr $localx $localy "${dim} ○ ${off}"
                   printf "$dotpr"
                fi
                mesg "entered wormhole at $wormx,$wormy"
                holeanim
                break
             fi
          else
             (( newquad = 1 )) # travelled outside local quad
             break
          fi
       done

       if (( newquad )); then
          (( wormgo[qindex] > 1 )) && unset wormgo[qindex] # remove wormhole if ever active
          (( entx=destx, enty=desty )) 
          # in a new quad, update globals
          coordsetup
          quadpop lquad galaxy
          holeplace=
          statscreen -q
          unset gllrsbuf glmapbuf glsrsbuf
          view= # to force a short range scan
       else
          # rest of coordsetup not nec
          (( entind = (localy << 3) + localx ))
       fi

       # only navigation can change docked status
       if isdocked; then
          (( docked=1 ))
          replenish
          statscreen -st # we do ce below
       else
          (( docked = 0 ))
       fi 

       # any navigation makes the enterprise locator string stale
       unset entplace

       if [[ $view != SRS ]]; then
          shortrangescan lquad
       else
          srsbuf movestr $origx $origy "${dim} · ${off}"
          srsbuf movestr $localx $localy "${cya}-E-${off}"
          printf "$movestr"
       fi
       statscreen -ce
    fi
 else
    mesg "insufficient warp energy"
 fi

}

galaxinit () {

 local -i tmp kli i j q r
 local -n lgalax=$1
 
 # provisional number of quads with klingons or a base
 local -a quadlist=() 
 
 for ((i=0; i<64; i++)); do
    (( i != qindex )) && quadlist+=($i)
 done
 
 # shuffle just the tail of the list - for klingon and base quads
 for (( i=62; i>=54; i-- )); do
    (( j = RANDOM % (i + 1) ))
    (( tmp = quadlist[i], quadlist[i] = quadlist[j], quadlist[j] = tmp ))
 done

 # insert stars and wormhole no go
 for (( q=0; q<64; q++ )); do
    (( r = RANDOM ))
    (( lgalax[q] = 2 + (r % 3) ))
    (( r % 5 )) || (( wormgo[q] = 1 ))
 done

 # insert starbases into the first two quads we picked
 for i in 62 61; do
    (( lgalax[quadlist[i]]+=10 ))
 done
 
 # and klingons into the rest
 for (( i=60; i>=54; i-- )); do
    if (( i > 58 )); then
       (( kli = 4))
    elif ((galkli > 11 )); then
       (( kli = 16 - galkli ))
    else
       (( kli = 1 + (RANDOM % 4 ) ))
    fi

    (( lgalax[quadlist[i]] += kli * 100 ))
    (( (galkli += kli) == 16 )) && break
 done

}

torpedo () {

 if ! [[ $view == SRS ]]; then
    shortrangescan lquad
    printf $cmdpos
 fi

 if (( torps == 0 )); then
    mesg "out of torpedoes"
 else
    if (( docked )); then
       mesg "weapon operation not permitted while docked"
    else
       local -i tvect
       getnum "vector" 7 tvect

       local -n tquad=$1
       local -i tx=$localx
       local -i ty=$localy
       local -i idx
       local tpr
      
       (( torps-- ))
      
       while : ; do
          (( tx+=xmult[tvect], ty+=ymult[tvect] ))
          if ! inrange 7 $tx $ty; then
             mesg "torpedo missed"
             break
          else
             (( idx= (ty << 3) + tx ))
             if ! [[ -v tquad[idx] ]]; then
                tpr= ; srsbuf tpr $tx $ty " ✧${off}" ; printf "$tpr"
                sleep 0.3
                tpr= ; srsbuf tpr $tx $ty "$dim ·${off}" ; printf "$tpr"
             else
                case ${tquad[idx]} in
                  3) # whacked a klingon
                     for (( i=0; i<quadkli; i++ )); do
                        (( klix[i] == tx && kliy[i] == ty )) && delklingon $i $idx
                     done ;;
   
                  1) mesg "torpedo absorbed by star at ${tx},${ty}" ;;
                  5) mesg "torpedo entered wormhole at ${tx},${ty}!" ;;
                  2) mesg "torpedo neutralised by starbase" 
                esac
                break
             fi
          fi 
       done
       # delklingon will update -k
       statscreen -t
    fi
 fi
}

#######  M A I N  #######

# turn screen echoing off
stty -echo

# effects
dim=$'\e[2m'
bol=$'\e[1m'
red=$'\e[31m'
grn=$'\e[32m'
yel=$'\e[33m'
cya=$'\e[36m'
off=$'\e[0m'

# cursor movement

declare -ir bottom=$(tput lines)

declare -a statb
for i in {13..17} 19 20 ; do
   statb[i]=$(tput cup $(( bottom - i )) 44)
done 

msgpos=$(tput cup $(( bottom - 6 )) 0)
dirpos=$(tput cup $(( bottom - 11 )) 0)
cmdpos=$(tput cup $bottom 0)
toppos=$(tput cup $(( bottom - 20 )) 0)
curoff=$'\e[?25l'   # hide cursor
curnorm=$'\e[?25h'  # show cursor

# game over messages (for the banner function)
declare -A overmessage=(
  [des]="  ENTERPRISE DESTROYED"
  [tim]="  MISSION TIME ELAPSED"
  [win]=" ALL KLINGONS DESTROYED"
  [str]="ENTERPRISE DEAD IN SPACE"
  [res]="  RESIGNATION ACCEPTED"
)

# commands
CMDS="-NAV-SRS-LRS-TOR-PHA-SHI-MAP-RES"

# initialise local quadrant and galaxy
declare -ia galaxy lquad
declare -ia quadvisit

# set up some globals
declare -i galkli=0 docked=0 stardate=131240
## 131350

# energy, shields, torpedoes, klingons in current quad
declare -i energy shields torps quadkli
replenish

gameover=

# navigation multipliers
declare -ia xmult=(0 1 1 1 0 -1 -1 -1)
declare -ia ymult=(-1 -1 0 1 1 1 0 -1)

# enterprise position in all 64 * 64 cells

declare -i rnd=$RANDOM
declare -i entx=$(( rnd & 63 ))
declare -i enty=$(( (rnd >> 6) & 63 ))

# which quadrant, and which cell we're in

declare -i quadx quady qindex
declare -i localx localy
declare -i entind cachelen

coordsetup # assign the above

declare -i sbsx sbsy # local quad starbase co-ords
declare -i wormx wormy # local quad wormhole co-ords
declare -i wormind # 1D of above

declare -ia seen # quadrants that are "seen" for the galaxy map
declare -ia wormgo # done or off limits for wormholes

# cached data
declare -a starcache klicache objlist scangrids
declare -a basecache

view=
holeplace=

printf '\033[2J\033[H' # clear
printf "%s" "$curoff"

galaxinit galaxy
quadpop lquad galaxy
blankgrid # set up the wormhole animation canvas

shortrangescan lquad
drawlabels
statscreen -qcdekst

while ! [[ $gameover ]] ; do
   # LRS / SRS / MAP not allowed if already active
   cmd cmdstr ${CMDS/-${view}/}

   case $cmdstr in
      NAV) navigate ;;
      TOR) torpedo lquad ;;
      LRS) longrangescan ;;
      SRS) shortrangescan lquad ;;
      SHI) shieldadjust ;;
      PHA) phaserfire ;;
      MAP) galaxymap ;;
      RES) resign # can set gameover
   esac

   (( quadcnt++ )) # another move in the same quad

   if ! (( ++stardate % 10 )); then
      statscreen -d
      if (( stardate == 131410 )); then
          mesg "mission time elapsed"
          gameover=tim
      fi
   fi

   ((galkli == 0)) && gameover=win

   # can set gameover on Ent destruction
   ! [[ $gameover ]] && klingonresponse 

   if ! [[ $gameover ]] && (( shields + energy == 0 )); then
      gameover=str
      mesg "energy resources exhausted"
      mesg "warp engines offline"
   fi

   if ! [[ $gameover ]]; then
      wormhole
      (( ${#quadvisit[@]} > 5 )) && garbagecollect
   fi
done

banner "${overmessage[$gameover]}"

# restore terminal normality
printf "%s%s" "$curnorm" "$cmdpos"
stty echo

exit 0

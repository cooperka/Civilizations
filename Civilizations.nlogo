extensions [ array table ]

globals [
  civ-colors           ;; Array of which color represents which civ
  resource-color-nums  ;; Array of which color represents which resource
  resource-names       ;; A table to get the resource 'word' based on color
  workers-made         ;; Track total global workers made
  soldiers-made        ;; Track total global soldiers made
  units-killed         ;; Track total global units killed
  ticks-since-kill     ;; Prevent bug where soldiers get stuck at an enemy base
]

breed [ civs civ ]          ;; Civilizations
breed [ workers worker ]    ;; Workers to forage
breed [ soldiers soldier ]  ;; Soldiers to fight

civs-own [
  food  wood  stone  ;; Resource count
  bases-known?       ;; List which is True/False whether you know the coords of that civilization
]
workers-own [
  home-x  home-y  ;; Home coordinates
  home-civ        ;; Handle to the civ who spawned you
  health          ;; Workers only have 1 health
  carrying        ;; 0 if nothing, [resource-color] if something
]
soldiers-own [
  home-x  home-y  ;; Home coordinates
  home-civ        ;; Handle to the civ who spawned you
  health          ;; Soldiers start with 3 health
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Setup-related
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  setup-globals
  setup-patches
  setup-turtles
  reset-ticks
  verbose 9 "\n=== SETUP ==="
end

to setup-globals
  set civ-colors array:from-list [ blue red orange cyan pink ]
  
  set resource-color-nums array:from-list [ 44 63 4 ] ;; Food, wood, stone
  
  set resource-names table:make
  table:put resource-names 44 "food"
  table:put resource-names 63 "wood"
  table:put resource-names 4 "stone"
end

to setup-patches
  repeat num-resources [
    let resource-index random 3 ;; Food / wood / stone
    let resource-color getResourceColor resource-index
    
    ;; Choose a random patch, and set it to a particular color
    ;; Keep choosing patches in the boundary of that patch, and fill them with the same color
    ;; Do this a number of times determined by resource-amnt
    ask patch random-xcor random-ycor [
      set pcolor resource-color
      let boundary patch-set neighbors
      repeat (random-normal resource-amnt sqrt resource-amnt) [
        let choice one-of boundary with [ pcolor = black ]
        if choice != nobody [
          ask choice [
            set pcolor resource-color
            set boundary (patch-set boundary neighbors)  ;; Increase the boundary to include this new patch's neighbors
          ]
        ]
      ]
    ]
  ]
end

to setup-turtles
  ;; Create the civs (home-squares)
  create-civs num-civs [
    setxy random-xcor random-ycor
    set shape "star"
    set size 5
    set color getCivColor who
    set food 0
    set wood 0
    set stone 0
    set bases-known? n-values num-civs [ false ]  ;; Initially they know nothing of the locations of enemies
  ]
  
  ;; Create some initial workers
  ask civs [
    spawn 3 "workers"
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Go-related
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if check-loss [ stop ] ;; Stop if EVERYONE is gone except for one
  move-workers           ;; Forage, or return home
  move-soldiers          ;; Fight, or move
  spy                    ;; Any of your soldiers in range of an enemy base will "find" it
  spawn-more             ;; Create more workers/soldiers if possible
  check-stalemate        ;; Prevent bug where soldiers get stuck at an enemy base
  tick
end

to-report check-loss
  ask civs [
    ;; Die if you don't have any units left
    if count turtles with [ color = [color] of myself ] = 1 [
      verbose 10 (word "CIV " who " HAS LOST!")
      ask civs [ set bases-known? replace-item [who] of myself bases-known? false ]  ;; Make everyone else forget you existed
      die
    ]
  ]
  if count civs = 1 [ report true ]  ;; Game over
  report false                       ;; Continue running
end

to move-workers
  ask workers [
    ifelse carrying = 0
      [ forage ]        ;; You don't have anything, so go find something
      [ return-home ]   ;; You have something, so return home
  ]
end

to move-soldiers
  ask soldiers [
    if not fight   ;; Attack the enemy below you if there is one
    [ move ]       ;; Move towards the nearest enemy
  ]
end

to spy
  ;; Turtles who come close to another base will "find" the base
  ;; The coordinates of the base are saved in the turtle's own civ variables
  ;; Depending on strategy, soldiers may purposely gravitate toward enemy bases
  ask civs [
    let who-handle who
    ask turtles in-radius line-of-sight with [ color != [color] of myself and breed != civs ] [
      ;; If you haven't already discovered the location of the enemy, do so now
      if item ([who] of myself) ([bases-known?] of home-civ) = false [
        verbose 6 (word self " " home-civ " has discovered the location of " myself)
        ask home-civ [ set bases-known? replace-item who-handle bases-known? true ]
      ]
    ]
  ]
end

to spawn-more
  ask civs
  [
    if build-strategy who = "none" [
      ;; Randomly choose which one to try to build first
      ifelse random 2 = 0
        [ build-preferentially "workers" ]
        [ build-preferentially "soldiers" ]
      stop
    ]
    
    if build-strategy who = "balanced" [
      ;; Preferentially build whichever you have less of
      ifelse (count workers with [ color = [color] of myself ]) <= (count soldiers with [ color = [color] of myself ])
        [ build-preferentially "workers" ]
        [ build-preferentially "soldiers" ]
      stop
    ]
    
    ;; Default case (build-strategy = "workers" or "soldiers")
    build-preferentially build-strategy who
  ]
end

to check-stalemate
  ;; Sometimes, with the "attack" strategy, if ONLY soldiers remain for two different civs, they will get stuck
  ;; Each of them have soldiers surrounding the enemy, but since the soldiers are away from home they never see each other
  ;; This resets the strategy if they get "stuck" like this
  if your-fight-strategy = "attack" and their-fight-strategy = "attack" [
    set ticks-since-kill ticks-since-kill + 1
    if ticks-since-kill > 2000 [
      verbose 5 "Resetting strategy"
      set your-fight-strategy "none"
      set their-fight-strategy "none"
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Civs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Civs function
to spawn [ num class ]
  verbose 2 (word "Civ " who " creates " num " " class)
  
  hatch num [
    if class = "workers" [
      set breed workers
      set shape "person"
      set size 3
      set health 1
      set carrying 0
      
      set workers-made workers-made + 1     ;; For behaviorspace
    ]
    if class = "soldiers" [
      set breed soldiers
      set shape "orbit 3"
      set size 4
      set health 3
      
      set soldiers-made soldiers-made + 1   ;; For behaviorspace
    ]
    
    ;; Traits common to all
    facexy random-xcor random-ycor
    set color color
    set home-x round xcor
    set home-y round ycor
    set home-civ myself    ;; Handle to refer back to your own civilization
  ]
end

;; Civs function
to build-preferentially [ preference ]
  ;; Try to build whichever you are told first, then try to build the opposite type
  ;; The order is significant because you may run out of resources when building the first type
  if preference = "workers" [
    try-workers
    try-soldiers
    stop
  ]
  if preference = "soldiers" [
    try-soldiers
    try-workers
    stop
  ]
  user-message "ERROR: build-pref"
end

;; Civs function
to try-workers
  if food > 4 and wood > 1 and stone > 1 [
    ;; Build a worker
    spawn 1 "workers"
    set food food - 4
    set wood wood - 1
    set stone stone - 1
  ]
end

;; Civs function
to try-soldiers
  if food > 1 and wood > 3 and stone > 3 [
    ;; Build a soldier
    spawn 1 "soldiers"
    set food food - 1
    set wood wood - 3
    set stone stone - 3
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Workers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Workers function
to forage
  ifelse pcolor = black
    ;; Look for a nearby resource
    ;; Optimality of resource is determined by how far away it is
    ;; If a build-preference is chosen, this also factors in
    [
      let my-color color            ;; Reference to your own color (to send to patch function)
      let my-who [who] of home-civ  ;; Reference to your civ's who number (to send to patch function)
      let choice min-one-of patches in-radius line-of-sight with [ pcolor != black ]
                            [ optimal-patch (distance myself) pcolor my-color my-who ]
      if choice != nobody [ face choice ]
      fd 1
    ]
    ;; Otherwise take the resource you are already on
    [
      verbose 0 (word color " has found " pcolor)
      set carrying pcolor
      ask patch-here [ set pcolor black ]
    ]
end

;; Patches function
to-report optimal-patch [ dist pcol my-color my-who ]
  ;; Optimality of resource is determined by how far away it is
  ;; If a build-preference is chosen, this also factors in
  
  ;; TODO this isn't quite optimal (e.g. if there is a surplus of food and NO stone)
  ;; But it works well enough for this model
  
  if build-strategy my-who = "none" [ report dist ]
  if build-strategy my-who = "workers" [
    ifelse pcol = getResourceColor 0
      [ report dist - line-of-sight ] ;; Food (preferred)
      [ report dist ]                 ;; Wood or stone
  ]
  if build-strategy my-who = "soldiers" [
    ifelse pcol = getResourceColor 0
      [ report dist ]                 ;; Food
      [ report dist - line-of-sight ] ;; Wood or stone (preferred)
  ]
  if build-strategy my-who = "balanced" [
    ;; diff is negative if there are more soldiers, positive if more workers
    let diff (count workers with [ color = my-color ]) - (count soldiers with [ color = my-color ])
    
    ifelse diff > 0
    ;; There are currently more workers
    [
      ifelse pcol = getResourceColor 0
      [ report dist ]                 ;; Food
      [ report dist - line-of-sight ] ;; Wood or stone (preferred)
    ]
    ;; Otherwise there are currently more soldiers
    [
      ifelse pcol = getResourceColor 0
      [ report dist - line-of-sight ] ;; Food (preferred)
      [ report dist ]                 ;; Wood or stone
    ]
  ]
  report dist  ;; To shut up a useless warning
end

;; Workers function
to return-home
  ifelse round xcor = home-x and round ycor = home-y
    ;; You are home! Drop off the resources you were carrying
    [
      verbose 0 (word color " has returned " carrying)
      increaseResource home-civ (getResourceName carrying) 1
      set carrying 0
    ]
    ;; Otherwise keep trying to get home
    [
      facexy home-x home-y
      fd 1
    ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Soldiers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Soldiers function
to-report fight
  ;; Attack a neighbor if there is one
  let choice one-of (turtles-on neighbors) with [ color != [color] of myself and not is-civ? self ]
  if choice != nobody [
    ask choice [
      verbose 3 (word [home-civ] of myself " " myself " attacking " home-civ " " choice)
      set health health - 1
      ifelse health = 0
        ;; They have been killed!
        [
          verbose 4 (word home-civ " " choice " has died")
          set units-killed units-killed + 1  ;; For behaviorspace
          die
        ]
        ;; Otherwise set the shape to represent how much health remains
        [
          set shape (word "orbit " health) ;; Decrease the number of "circles" along your ring
        ]
    ]
    report true  ;; Successfully attacked, so don't do anything else
  ]
  report false   ;; Didn't attack, so move instead
end

;; Soldiers function
to move
  ;; Head toward the nearest enemy
  let choice min-one-of (turtles in-radius line-of-sight) with
    [ (color != [color] of myself) and (not is-civ? self) ] [ distance myself ]
  ifelse choice != nobody
    [ face choice ] ;; attack an enemy if you see one
    [
      if fight-strategy [who] of home-civ = "mass" [ face-group ]  ;; Regroup into a squadron if no enemies are around
      if fight-strategy [who] of home-civ = "attack" [ find-base ]  ;; Head toward an enemy base
      ;; if "None" don't do anything special
    ]
  fd 1  ;; Move forward (after potentially changing the direction you face in the functions above)
end

;; Soldiers function
to face-group
  ;; Face the "oldest" soldier on your team
  let choice min-one-of soldiers with [ color = [color] of myself ] [ who ]
  if (choice != nobody) and (choice != self) [ face choice ]
end

;; Soldiers function
to find-base
  ;; Face an enemy base, if you know where one is
  let options filter [ ? = true ] ([bases-known?] of home-civ)
  if not empty? options [
    let flag false  ;; flag remains false until you face an enemy
    while [ flag = false ] [
      ;; Randomly pick civs until you find one with the value 'true'
      ;; This is not the most elegant way of going about it, but is the easiest with this setup
      let rand random num-civs
      if item rand ([bases-known?] of home-civ) = true [
        face civ rand
        set flag true
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Resources
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to increaseResource [ civ resource-type val ]
  ;; Incease the resource count of the type of resource specified
  if resource-type = "food" [ ask civ [ set food (food + val) ] ]
  if resource-type = "wood" [ ask civ [ set wood (wood + val) ] ]
  if resource-type = "stone" [ ask civ [ set stone (stone + val) ] ]
end

to-report getResourceName [ resource-color ]
  ;; e.g. convert from color [44] to "food"
  report table:get resource-names resource-color
end

to-report getResourceColor [ resource-index ]
  ;; e.g. convert from index [0] to color [44]
  report array:item resource-color-nums resource-index
end

to-report getCivColor [ civ-num ]
  ;; e.g. convert from index [0] to color [blue]
  report array:item civ-colors civ-num
end

;; Used by the monitors
to-report getResources [ civ-num ]
  let return -1  ;; To shut up a useless warning
  ask civ civ-num [ set return (word food " " wood " " stone) ]
  report return
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Misc.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report build-strategy [ who-num ]
  ;; Report strategy based on who it is that's asking
  ;; You can choose a different strategy than your enemies do
  ifelse who-num = 0
    [ report your-build-strategy ]
    [ report their-build-strategy ]
  report "none"  ;; To shut up a useless warning
end

to-report fight-strategy [ who-num ]
  ;; Report strategy based on who it is that's asking
  ;; You can choose a different strategy than your enemies do
  ifelse who-num = 0
    [ report your-fight-strategy ]
    [ report their-fight-strategy ]
  report "none"  ;; To shut up a useless warning
end

to verbose [ num string ]
  ;; This easily changes the debugging output shown
  ;; Really for my personal use only
  if num >= 5 [ print string ]
end

to-report civ-win
  ;; Reports whether you (civ 0) won (for behaviorspace)
  if count civs > 1 [ report "NA" ]
  ifelse civ 0 != nobody
    [ report 1 ]  ;; You still exist, so you won!
    [ report 0 ]  ;; You lost
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
624
445
50
50
4.0
1
10
1
1
1
0
1
1
1
-50
50
-50
50
0
0
1
ticks
30.0

BUTTON
31
23
100
56
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
112
23
175
56
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
19
75
191
108
num-civs
num-civs
0
5
3
1
1
NIL
HORIZONTAL

SLIDER
19
113
191
146
num-resources
num-resources
0
200
120
1
1
NIL
HORIZONTAL

SLIDER
19
150
191
183
resource-amnt
resource-amnt
0
50
15
1
1
NIL
HORIZONTAL

MONITOR
644
15
701
60
Blue
getResources 0
2
1
11

MONITOR
711
14
768
59
Red
getResources 1
2
1
11

MONITOR
778
15
840
60
Orange
getResources 2
2
1
11

MONITOR
676
68
733
113
Cyan
getResources 3
2
1
11

MONITOR
743
68
800
113
Pink
getResources 4
2
1
11

SLIDER
19
189
192
222
line-of-sight
line-of-sight
0
10
3
1
1
patches
HORIZONTAL

PLOT
644
128
844
278
Population
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Blue" 1.0 0 -13345367 true "" "plot count turtles with [ color = getCivColor 0 ]"
"Red" 1.0 0 -2674135 true "" "plot count turtles with [ color = getCivColor 1 ]"
"Orange" 1.0 0 -955883 true "" "plot count turtles with [ color = getCivColor 2 ]"
"Cyan" 1.0 0 -11221820 true "" "plot count turtles with [ color = getCivColor 3 ]"
"Pink" 1.0 0 -2064490 true "" "plot count turtles with [ color = getCivColor 4 ]"

PLOT
644
287
844
437
Resources left
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count patches with [ pcolor != black ]"

CHOOSER
28
239
184
284
your-build-strategy
your-build-strategy
"none" "workers" "soldiers" "balanced"
0

CHOOSER
28
284
184
329
your-fight-strategy
your-fight-strategy
"none" "mass" "attack"
0

CHOOSER
27
341
183
386
their-build-strategy
their-build-strategy
"none" "workers" "soldiers" "balanced"
0

CHOOSER
28
385
184
430
their-fight-strategy
their-fight-strategy
"none" "mass" "attack"
0

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

orbit 1
true
0
Circle -7500403 true true 116 11 67
Circle -7500403 false true 41 41 218

orbit 2
true
0
Circle -7500403 true true 116 221 67
Circle -7500403 true true 116 11 67
Circle -7500403 false true 44 44 212

orbit 3
true
0
Circle -7500403 true true 116 11 67
Circle -7500403 true true 26 176 67
Circle -7500403 true true 206 176 67
Circle -7500403 false true 45 45 210

orbit 4
true
0
Circle -7500403 true true 116 11 67
Circle -7500403 true true 116 221 67
Circle -7500403 true true 221 116 67
Circle -7500403 false true 45 45 210
Circle -7500403 true true 11 116 67

orbit 5
true
0
Circle -7500403 true true 116 11 67
Circle -7500403 true true 13 89 67
Circle -7500403 true true 178 206 67
Circle -7500403 true true 53 204 67
Circle -7500403 true true 220 91 67
Circle -7500403 false true 45 45 210

orbit 6
true
0
Circle -7500403 true true 116 11 67
Circle -7500403 true true 26 176 67
Circle -7500403 true true 206 176 67
Circle -7500403 false true 45 45 210
Circle -7500403 true true 26 58 67
Circle -7500403 true true 206 58 67
Circle -7500403 true true 116 221 67

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Build-Strategy" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>civ-win</metric>
    <enumeratedValueSet variable="their-fight-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-fight-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-resources">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="their-build-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-civs">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="line-of-sight">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-build-strategy">
      <value value="&quot;none&quot;"/>
      <value value="&quot;workers&quot;"/>
      <value value="&quot;soldiers&quot;"/>
      <value value="&quot;balanced&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="resource-amnt">
      <value value="15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Fight-Strategy" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>civ-win</metric>
    <enumeratedValueSet variable="their-fight-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-fight-strategy">
      <value value="&quot;none&quot;"/>
      <value value="&quot;mass&quot;"/>
      <value value="&quot;attack&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-resources">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="their-build-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-civs">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="line-of-sight">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-build-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="resource-amnt">
      <value value="15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Optimal" repetitions="200" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>civ-win</metric>
    <enumeratedValueSet variable="their-fight-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-fight-strategy">
      <value value="&quot;attack&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-resources">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="their-build-strategy">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-civs">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="line-of-sight">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="your-build-strategy">
      <value value="&quot;soldiers&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="resource-amnt">
      <value value="15"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@

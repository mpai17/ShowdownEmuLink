; ShowdownBattleInit
; Sets up and runs a link-style battle with preset parties (6 diverse Pokemon).
; Uses table-driven approach: SpeciesTable, TemplateTable, NicknameTable.
; After the battle ends, transitions to black and starts a new battle.

ShowdownBattleInit::
	; Load graphics needed for battle
	call LoadFontTilePatterns
	call LoadHpBarAndStatusTilePatterns
	callfar LoadTrainerInfoTextBoxTiles

	; Set player name = "PLAYER"
	ld hl, .playerName
	ld de, wPlayerName
	ld bc, NAME_LENGTH
	call CopyData

	; Set player ID
	ld a, $01
	ld [wPlayerID], a
	ld a, $23
	ld [wPlayerID + 1], a

	; --- Set up player party ---
	ld a, PARTY_LENGTH
	ld [wPartyCount], a

	; Fill wPartySpecies from SpeciesTable + $FF terminator
	ld hl, SpeciesTable
	ld de, wPartySpecies
	ld b, PARTY_LENGTH
.fillPlayerSpecies
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .fillPlayerSpecies
	ld a, $FF
	ld [de], a

	; Copy 6 different templates into wPartyMons
	ld de, wPartyMons
	ld hl, TemplateTable
	ld b, PARTY_LENGTH
.copyPlayerMons
	push bc
	; Read pointer from TemplateTable
	ld a, [hli]
	ld c, a
	ld a, [hli]
	push hl          ; save table position
	ld h, a
	ld l, c           ; hl = template pointer
	ld bc, PARTYMON_STRUCT_LENGTH
	call CopyData     ; copies from hl to de, advances de
	pop hl            ; restore table position
	pop bc
	dec b
	jr nz, .copyPlayerMons

	; Fill player OT names (6 entries, NAME_LENGTH each)
	ld de, wPartyMonOT
	ld b, PARTY_LENGTH
.fillPlayerOT
	push bc
	ld hl, .playerName
	ld bc, NAME_LENGTH
	call CopyData
	pop bc
	dec b
	jr nz, .fillPlayerOT

	; Fill player nicknames from NicknameTable
	ld de, wPartyMonNicks
	ld hl, NicknameTable
	ld b, PARTY_LENGTH
.fillPlayerNicks
	push bc
	ld bc, NAME_LENGTH
	call CopyData     ; copies NAME_LENGTH bytes from hl to de, advances both
	pop bc
	dec b
	jr nz, .fillPlayerNicks

	; --- Set up enemy party ---
	ld a, PARTY_LENGTH
	ld [wEnemyPartyCount], a

	; Fill wEnemyPartySpecies from SpeciesTable + $FF terminator
	ld hl, SpeciesTable
	ld de, wEnemyPartySpecies
	ld b, PARTY_LENGTH
.fillEnemySpecies
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .fillEnemySpecies
	ld a, $FF
	ld [de], a

	; Copy 6 different templates into wEnemyMons
	ld de, wEnemyMons
	ld hl, TemplateTable
	ld b, PARTY_LENGTH
.copyEnemyMons
	push bc
	; Read pointer from TemplateTable
	ld a, [hli]
	ld c, a
	ld a, [hli]
	push hl
	ld h, a
	ld l, c
	ld bc, PARTYMON_STRUCT_LENGTH
	call CopyData
	pop hl
	pop bc
	dec b
	jr nz, .copyEnemyMons

	; Fill enemy OT names
	ld de, wEnemyMonOT
	ld b, PARTY_LENGTH
.fillEnemyOT
	push bc
	ld hl, .enemyName
	ld bc, NAME_LENGTH
	call CopyData
	pop bc
	dec b
	jr nz, .fillEnemyOT

	; Fill enemy nicknames from NicknameTable
	ld de, wEnemyMonNicks
	ld hl, NicknameTable
	ld b, PARTY_LENGTH
.fillEnemyNicks
	push bc
	ld bc, NAME_LENGTH
	call CopyData
	pop bc
	dec b
	jr nz, .fillEnemyNicks

	; Set enemy trainer name
	ld hl, .enemyName
	ld de, wLinkEnemyTrainerName
	ld bc, NAME_LENGTH
	call CopyData

	; Check wShowdownConnected to determine link state
	ld a, [wShowdownConnected]
	and a
	jr nz, .onlineMode

	; Offline mode: AI controls enemy
	ld a, LINK_STATE_IN_CABLE_CLUB
	ld [wLinkState], a
	jr .setOpponent

.onlineMode
	; Online mode: Showdown controls enemy (stubbed for now)
	ld a, LINK_STATE_BATTLING
	ld [wLinkState], a

.setOpponent
	; Set opponent type (standard link battle opponent)
	ld a, OPP_RIVAL1
	ld [wCurOpponent], a

	; Clear screen and set palette
	call ClearScreen
	ld b, SET_PAL_BATTLE_BLACK
	call RunPaletteCommand
	call Delay3
	call GBPalNormal

	; Run the full battle
	predef InitOpponent

	; Battle has ended -- transition to black
	call ClearScreen
	call ClearSprites
	ld a, $FF
	ldh [rBGP], a
	ldh [rOBP0], a
	ldh [rOBP1], a
	call Delay3

	; Heal player party for next battle
	predef HealParty

	; Reset link state for next battle setup
	xor a
	ld [wLinkState], a
	ld [wBattleResult], a

	; Loop back for another battle
	jp ShowdownBattleInit

.playerName
	db "PLAYER@", 0, 0, 0, 0

.enemyName
	db "RIVAL@", 0, 0, 0, 0, 0

; --- Data Tables ---

; Species IDs for each party slot (6 entries)
SpeciesTable:
	db ALAKAZAM   ; Slot 0
	db STARMIE    ; Slot 1
	db SNORLAX    ; Slot 2
	db TAUROS     ; Slot 3
	db CHANSEY    ; Slot 4
	db EXEGGUTOR  ; Slot 5

; Pointers to each template (6 entries, 2 bytes each)
TemplateTable:
	dw AlakazamTemplate
	dw StarmieTemplate
	dw SnorlaxTemplate
	dw TaurosTemplate
	dw ChanseyTemplate
	dw ExeggutorTemplate

; Nicknames for each party slot (NAME_LENGTH = 11 bytes each)
NicknameTable:
	db "ALAKAZAM@", 0, 0    ; 11 bytes: 8 + 1(@) + 2(pad)
	db "STARMIE@", 0, 0, 0  ; 11 bytes: 7 + 1(@) + 3(pad)
	db "SNORLAX@", 0, 0, 0  ; 11 bytes: 7 + 1(@) + 3(pad)
	db "TAUROS@", 0, 0, 0, 0 ; 11 bytes: 6 + 1(@) + 4(pad)
	db "CHANSEY@", 0, 0, 0  ; 11 bytes: 7 + 1(@) + 3(pad)
	db "EXEGGUTOR@", 0      ; 11 bytes: 9 + 1(@) + 1(pad)

; --- Pokemon Templates (PARTYMON_STRUCT_LENGTH = 44 bytes each) ---

; Slot 0: Alakazam - L100, Perfect DVs, No EVs
; Moves: Psychic, Thunder Wave, Recover, Seismic Toss
; Base stats: HP=55, ATK=50, DEF=45, SPD=120, SPC=135
AlakazamTemplate:
	db ALAKAZAM       ; $00: Species
	db $00, $FA       ; $01-02: Current HP (250)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db PSYCHIC_TYPE   ; $05: Type 1
	db PSYCHIC_TYPE   ; $06: Type 2
	db 50             ; $07: Catch Rate
	db PSYCHIC_M      ; $08: Move 1
	db THUNDER_WAVE   ; $09: Move 2
	db RECOVER        ; $0A: Move 3
	db SEISMIC_TOSS   ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D0            ; $1D: PP Move 1 (Psychic, 3 PP Ups, 16/16)
	db $E0            ; $1E: PP Move 2 (Thunder Wave, 3 PP Ups, 32/32)
	db $E0            ; $1F: PP Move 3 (Recover, 3 PP Ups, 32/32)
	db $E0            ; $20: PP Move 4 (Seismic Toss, 3 PP Ups, 32/32)
	db 100            ; $21: Level
	db $00, $FA       ; $22-23: Max HP (250)
	db $00, $87       ; $24-25: Attack (135)
	db $00, $7D       ; $26-27: Defense (125)
	db $01, $13       ; $28-29: Speed (275)
	db $01, $31       ; $2A-2B: Special (305)

; Slot 1: Starmie - L100, Perfect DVs, No EVs
; Moves: Surf, Psychic, Thunderbolt, Recover
; Base stats: HP=60, ATK=75, DEF=85, SPD=115, SPC=100
StarmieTemplate:
	db STARMIE        ; $00: Species
	db $01, $04       ; $01-02: Current HP (260)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db WATER          ; $05: Type 1
	db PSYCHIC_TYPE   ; $06: Type 2
	db 60             ; $07: Catch Rate
	db SURF           ; $08: Move 1
	db PSYCHIC_M      ; $09: Move 2
	db THUNDERBOLT    ; $0A: Move 3
	db RECOVER        ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D8            ; $1D: PP Move 1 (Surf, 3 PP Ups, 24/24)
	db $D0            ; $1E: PP Move 2 (Psychic, 3 PP Ups, 16/16)
	db $D8            ; $1F: PP Move 3 (Thunderbolt, 3 PP Ups, 24/24)
	db $E0            ; $20: PP Move 4 (Recover, 3 PP Ups, 32/32)
	db 100            ; $21: Level
	db $01, $04       ; $22-23: Max HP (260)
	db $00, $B9       ; $24-25: Attack (185)
	db $00, $CD       ; $26-27: Defense (205)
	db $01, $09       ; $28-29: Speed (265)
	db $00, $EB       ; $2A-2B: Special (235)

; Slot 2: Snorlax - L100, Perfect DVs, No EVs
; Moves: Body Slam, Earthquake, Ice Beam, Rest
; Base stats: HP=160, ATK=110, DEF=65, SPD=30, SPC=65
SnorlaxTemplate:
	db SNORLAX        ; $00: Species
	db $01, $CC       ; $01-02: Current HP (460)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db NORMAL         ; $05: Type 1
	db NORMAL         ; $06: Type 2
	db 25             ; $07: Catch Rate
	db BODY_SLAM      ; $08: Move 1
	db EARTHQUAKE     ; $09: Move 2
	db ICE_BEAM       ; $0A: Move 3
	db REST           ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D8            ; $1D: PP Move 1 (Body Slam, 3 PP Ups, 24/24)
	db $D0            ; $1E: PP Move 2 (Earthquake, 3 PP Ups, 16/16)
	db $D0            ; $1F: PP Move 3 (Ice Beam, 3 PP Ups, 16/16)
	db $D0            ; $20: PP Move 4 (Rest, 3 PP Ups, 16/16)
	db 100            ; $21: Level
	db $01, $CC       ; $22-23: Max HP (460)
	db $00, $FF       ; $24-25: Attack (255)
	db $00, $A5       ; $26-27: Defense (165)
	db $00, $5F       ; $28-29: Speed (95)
	db $00, $A5       ; $2A-2B: Special (165)

; Slot 3: Tauros - L100, Perfect DVs, No EVs
; Moves: Body Slam, Earthquake, Blizzard, Hyper Beam
; Base stats: HP=75, ATK=100, DEF=95, SPD=110, SPC=70
TaurosTemplate:
	db TAUROS         ; $00: Species
	db $01, $22       ; $01-02: Current HP (290)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db NORMAL         ; $05: Type 1
	db NORMAL         ; $06: Type 2
	db 45             ; $07: Catch Rate
	db BODY_SLAM      ; $08: Move 1
	db EARTHQUAKE     ; $09: Move 2
	db BLIZZARD       ; $0A: Move 3
	db HYPER_BEAM     ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D8            ; $1D: PP Move 1 (Body Slam, 3 PP Ups, 24/24)
	db $D0            ; $1E: PP Move 2 (Earthquake, 3 PP Ups, 16/16)
	db $C8            ; $1F: PP Move 3 (Blizzard, 3 PP Ups, 8/8)
	db $C8            ; $20: PP Move 4 (Hyper Beam, 3 PP Ups, 8/8)
	db 100            ; $21: Level
	db $01, $22       ; $22-23: Max HP (290)
	db $00, $EB       ; $24-25: Attack (235)
	db $00, $E1       ; $26-27: Defense (225)
	db $00, $FF       ; $28-29: Speed (255)
	db $00, $AF       ; $2A-2B: Special (175)

; Slot 4: Chansey - L100, Perfect DVs, No EVs
; Moves: Ice Beam, Thunderbolt, Thunder Wave, Recover
; Base stats: HP=250, ATK=5, DEF=5, SPD=50, SPC=105
ChanseyTemplate:
	db CHANSEY        ; $00: Species
	db $02, $80       ; $01-02: Current HP (640)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db NORMAL         ; $05: Type 1
	db NORMAL         ; $06: Type 2
	db 30             ; $07: Catch Rate
	db ICE_BEAM       ; $08: Move 1
	db THUNDERBOLT    ; $09: Move 2
	db THUNDER_WAVE   ; $0A: Move 3
	db RECOVER        ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D0            ; $1D: PP Move 1 (Ice Beam, 3 PP Ups, 16/16)
	db $D8            ; $1E: PP Move 2 (Thunderbolt, 3 PP Ups, 24/24)
	db $E0            ; $1F: PP Move 3 (Thunder Wave, 3 PP Ups, 32/32)
	db $E0            ; $20: PP Move 4 (Recover, 3 PP Ups, 32/32)
	db 100            ; $21: Level
	db $02, $80       ; $22-23: Max HP (640)
	db $00, $2D       ; $24-25: Attack (45)
	db $00, $2D       ; $26-27: Defense (45)
	db $00, $87       ; $28-29: Speed (135)
	db $00, $F5       ; $2A-2B: Special (245)

; Slot 5: Exeggutor - L100, Perfect DVs, No EVs
; Moves: Psychic, Explosion, Mega Drain, Rest
; Base stats: HP=95, ATK=95, DEF=85, SPD=55, SPC=125
ExeggutorTemplate:
	db EXEGGUTOR      ; $00: Species
	db $01, $4A       ; $01-02: Current HP (330)
	db 100            ; $03: Box Level
	db 0              ; $04: Status
	db GRASS          ; $05: Type 1
	db PSYCHIC_TYPE   ; $06: Type 2
	db 65             ; $07: Catch Rate
	db PSYCHIC_M      ; $08: Move 1
	db EXPLOSION      ; $09: Move 2
	db MEGA_DRAIN     ; $0A: Move 3
	db REST           ; $0B: Move 4
	db $01, $23       ; $0C-0D: OT ID
	db $0F, $42, $40  ; $0E-10: Experience (1,000,000)
	dw 0              ; $11-12: HP EV
	dw 0              ; $13-14: ATK EV
	dw 0              ; $15-16: DEF EV
	dw 0              ; $17-18: SPD EV
	dw 0              ; $19-1A: SPC EV
	db $FF, $FF       ; $1B-1C: DVs (perfect)
	db $D0            ; $1D: PP Move 1 (Psychic, 3 PP Ups, 16/16)
	db $C8            ; $1E: PP Move 2 (Explosion, 3 PP Ups, 8/8)
	db $D0            ; $1F: PP Move 3 (Mega Drain, 3 PP Ups, 16/16)
	db $D0            ; $20: PP Move 4 (Rest, 3 PP Ups, 16/16)
	db 100            ; $21: Level
	db $01, $4A       ; $22-23: Max HP (330)
	db $00, $E1       ; $24-25: Attack (225)
	db $00, $CD       ; $26-27: Defense (205)
	db $00, $91       ; $28-29: Speed (145)
	db $01, $1D       ; $2A-2B: Special (285)

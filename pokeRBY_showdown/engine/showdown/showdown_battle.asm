; ShowdownBattle
; Functions that override RNG-based battle logic with predetermined
; values from the Showdown server, written into WRAM by the JS bridge.

; GetShowdownOverrideBase
; Returns HL pointing to the correct override slot (M1 or M2)
; based on hWhoseTurn and wSD_WhoFirst.
; If hWhoseTurn == wSD_WhoFirst, use M1 (first mover); else M2 (second mover).
; Destroys: a, b
GetShowdownOverrideBase:
	ldh a, [hWhoseTurn]
	ld b, a
	ld a, [wSD_WhoFirst]
	cp b
	jr nz, .useM2
	ld hl, wSD_M1_DamageHi
	ret
.useM2
	ld hl, wSD_M2_DamageHi
	ret

; ShowdownExchangeData
; Replaces LinkBattleExchangeData when wShowdownConnected != 0.
; Player's action is already in wSerialExchangeNybbleSendData.
; Sets wSD_Phase = 1, displays "Waiting...!", polls wSD_TurnReady.
; When ready, reads enemy action from wSerialExchangeNybbleReceiveData
; (written by JS), clears wSD_TurnReady, sets wSD_Phase = 3, returns.
ShowdownExchangeData::
	; Player's chosen action is already written to wSerialExchangeNybbleSendData
	; by the existing link battle code before calling LinkBattleExchangeData.

	; Signal JS that player has selected
	ld a, 1
	ld [wSD_Phase], a

	; Display "Waiting...!" text
	callfar PrintWaitingText

	; Poll loop: wait for JS to set wSD_Phase = 2 (turn_ready)
.pollLoop
	call DelayFrame

	; Check if JS has set phase to 2 (turn_ready)
	ld a, [wSD_Phase]
	cp 2
	jr nz, .pollLoop

	; Turn data is ready — advance to executing
	ld a, 3
	ld [wSD_Phase], a      ; signal turn executing

	ret

; ShowdownCriticalHitTest
; Reads crit flag from the override buffer instead of calculating from speed.
; Offset +2 in the override slot = crit byte.
ShowdownCriticalHitTest::
	call GetShowdownOverrideBase
	inc hl          ; skip DamageHi
	inc hl          ; skip DamageLo
	ld a, [hl]      ; read crit flag
	ld [wCriticalHitOrOHKO], a
	ret

; ShowdownSetDamage
; Reads exact 2-byte damage from override slot, writes to wDamage.
ShowdownSetDamage::
	call GetShowdownOverrideBase
	ld a, [hli]     ; DamageHi
	ld [wDamage], a
	ld a, [hl]      ; DamageLo
	ld [wDamage + 1], a
	ret

; ShowdownMoveHitTest
; Reads miss flag and effectiveness from override buffer.
; Offset +3 = miss byte, +4 = effectiveness byte.
ShowdownMoveHitTest::
	call GetShowdownOverrideBase
	inc hl          ; skip DamageHi
	inc hl          ; skip DamageLo
	inc hl          ; skip Crit
	ld a, [hli]     ; read miss flag
	ld [wMoveMissed], a
	ld a, [hl]      ; read effectiveness
	ld [wDamageMultipliers], a
	ret

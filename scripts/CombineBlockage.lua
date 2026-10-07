-- ============================================================
-- FS25_CombineBlockage.lua
-- by Marcus (Cobra Modding)
--
--
-- Version 1.1.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis.
-- ============================================================

CombineBlockage = {}
CombineBlockage.MOD_NAME = g_currentModName
CombineBlockage.IDLE_CUTTER_LOAD = 0
CombineBlockage.NORMAL_ZONE_END_LOAD = 80
CombineBlockage.NORMAL_ZONE_END_SPEED_KMH = 6
CombineBlockage.FULL_LOAD_SPEED_KMH = 7
CombineBlockage.BLOCK_SPEED_KMH = 8
CombineBlockage.LOAD_RISE_PER_SECOND = 64
CombineBlockage.LOAD_FALL_PER_SECOND = 64
CombineBlockage.INTAKE_RAMP_PER_SECOND = 2.5
CombineBlockage.DISPLAY_SMOOTHING_SPEED = 4
CombineBlockage.DRUM_BLOCKAGE_CHANCE = 0.05
CombineBlockage.DRUM_TRIGGER_LOAD = 80
CombineBlockage.DRUM_REARM_LOAD = 60
CombineBlockage.FEEDER_BLOCKAGE_CHANCE = 0.01  
CombineBlockage.FEEDER_TRIGGER_LOAD = 80
CombineBlockage.FEEDER_REARM_LOAD = 60

CombineBlockageClearEvent = {}
local CombineBlockageClearEvent_mt = Class(CombineBlockageClearEvent, Event)
InitEventClass(CombineBlockageClearEvent, "CombineBlockageClearEvent")

function CombineBlockageClearEvent.emptyNew()
    return Event.new(CombineBlockageClearEvent_mt)
end

function CombineBlockageClearEvent.new(vehicle, blockageType)
    local self = CombineBlockageClearEvent.emptyNew()
    self.vehicle = vehicle
    self.blockageType = blockageType
    return self
end

function CombineBlockageClearEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.blockageType = streamReadUIntN(streamId, 2)
    self:run(connection)
end

function CombineBlockageClearEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.blockageType, 2)
end

function CombineBlockageClearEvent:run(connection)
    if connection:getIsServer() or self.vehicle == nil or not self.vehicle.isServer then
        return
    end

    if self.blockageType == 1 then
        CombineBlockage.setBlocked(self.vehicle, false)
    elseif self.blockageType == 2 then
        CombineBlockage.setDrumBlocked(self.vehicle, false)
    elseif self.blockageType == 3 then
        CombineBlockage.setFeederBlocked(self.vehicle, false)
    end
end

function CombineBlockage.prerequisitesPresent(specializations)

    return SpecializationUtil.hasSpecialization(
        Combine,
        specializations
    )
        and SpecializationUtil.hasSpecialization(
            Drivable,
            specializations
        )
        and SpecializationUtil.hasSpecialization(
            Motorized,
            specializations
        )
end

function CombineBlockage.registerEventListeners(vehicleType)

    SpecializationUtil.registerEventListener(
        vehicleType,
        "onLoad",
        CombineBlockage
    )

    SpecializationUtil.registerEventListener(
        vehicleType,
        "onUpdateTick",
        CombineBlockage
    )

    SpecializationUtil.registerEventListener(
        vehicleType,
        "onDraw",
        CombineBlockage
    )

    SpecializationUtil.registerEventListener(
        vehicleType,
        "onRegisterActionEvents",
        CombineBlockage
    )

    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CombineBlockage)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CombineBlockage)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", CombineBlockage)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", CombineBlockage)
end

function CombineBlockage.registerOverwrittenFunctions(vehicleType)

    SpecializationUtil.registerOverwrittenFunction(
        vehicleType,
        "getCanMotorRun",
        CombineBlockage.getCanMotorRun
    )
end

function CombineBlockage:onLoad(savegame)

    self.spec_combineBlockage =
        self[
            "spec_"
            .. CombineBlockage.MOD_NAME
            .. ".combineBlockage"
        ]

    local spec = self.spec_combineBlockage

    spec.isBlocked = false
    spec.isDrumBlocked = false
    spec.isFeederBlocked = false

    spec.drumEventArmed = true
    spec.feederEventArmed = true

    spec.headerLoad = 0
    spec.displayLoad = 0
    spec.cropIntake = 0

    spec.clearBindingText = nil
    spec.clearDrumBindingText = nil

    spec.feederClearKeyWasDown = false

    spec.blockedCutterStates = nil
    spec.feederCombineWasTurnedOn = nil

    spec.actionEvents = {}
    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.lastSentHeaderLoad = 0
end

function CombineBlockage:onWriteStream(streamId, connection)
    if connection:getIsServer() then
        return
    end

    local spec = self.spec_combineBlockage
    streamWriteBool(streamId, spec.isBlocked)
    streamWriteBool(streamId, spec.isDrumBlocked)
    streamWriteBool(streamId, spec.isFeederBlocked)
    streamWriteFloat32(streamId, spec.headerLoad)
    streamWriteFloat32(streamId, spec.cropIntake)
end

function CombineBlockage:onReadStream(streamId, connection)
    if not connection:getIsServer() then
        return
    end

    local spec = self.spec_combineBlockage
    spec.isBlocked = streamReadBool(streamId)
    spec.isDrumBlocked = streamReadBool(streamId)
    spec.isFeederBlocked = streamReadBool(streamId)
    spec.headerLoad = streamReadFloat32(streamId)
    spec.cropIntake = streamReadFloat32(streamId)
    spec.displayLoad = spec.headerLoad
    CombineBlockage.refreshClientState(self, spec)
end

function CombineBlockage:onWriteUpdateStream(streamId, connection, dirtyMask)
    if connection:getIsServer() then
        return
    end

    local spec = self.spec_combineBlockage
    if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
        streamWriteBool(streamId, spec.isBlocked)
        streamWriteBool(streamId, spec.isDrumBlocked)
        streamWriteBool(streamId, spec.isFeederBlocked)
        streamWriteFloat32(streamId, spec.headerLoad)
        streamWriteFloat32(streamId, spec.cropIntake)
    end
end

function CombineBlockage:onReadUpdateStream(streamId, timestamp, connection)
    if not connection:getIsServer() then
        return
    end

    if streamReadBool(streamId) then
        local spec = self.spec_combineBlockage
        spec.isBlocked = streamReadBool(streamId)
        spec.isDrumBlocked = streamReadBool(streamId)
        spec.isFeederBlocked = streamReadBool(streamId)
        spec.headerLoad = streamReadFloat32(streamId)
        spec.cropIntake = streamReadFloat32(streamId)
        CombineBlockage.refreshClientState(self, spec)
    end
end

function CombineBlockage.refreshClientState(self, spec)
    if not self.isClient then
        return
    end

    spec.clearBindingText = spec.isBlocked and CombineBlockage.getClearBindingText() or nil
    spec.clearDrumBindingText = spec.isDrumBlocked and CombineBlockage.getDrumClearBindingText() or nil

    local headerEvent = spec.actionEvents[InputAction.COMBINEBLOCKAGE_CLEAR]
    if headerEvent ~= nil then
        g_inputBinding:setActionEventActive(headerEvent.actionEventId, spec.isBlocked)
    end

    local drumEvent = spec.actionEvents[InputAction.COMBINEBLOCKAGE_CLEAR_DRUM]
    if drumEvent ~= nil then
        g_inputBinding:setActionEventActive(drumEvent.actionEventId, spec.isDrumBlocked)
    end
end

function CombineBlockage.raiseDirtyFlag(self)
    if self.isServer then
        self:raiseDirtyFlags(self.spec_combineBlockage.dirtyFlag)
    end
end

function CombineBlockage.requestClear(self, blockageType)
    if self.isServer then
        if blockageType == 1 then
            CombineBlockage.setBlocked(self, false)
        elseif blockageType == 2 then
            CombineBlockage.setDrumBlocked(self, false)
        elseif blockageType == 3 then
            CombineBlockage.setFeederBlocked(self, false)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(CombineBlockageClearEvent.new(self, blockageType))
    end
end

function CombineBlockage:onUpdateTick(
    dt,
    isActiveForInput,
    isActiveForInputIgnoreSelection,
    isSelected
)

    local spec = self.spec_combineBlockage

    if self.isClient then

        CombineBlockage.updateFeederClearInput(
            self,
            spec,
            isActiveForInputIgnoreSelection
        )
    end

    if CombineBlockage.getIsHelperActive(self) then

        CombineBlockage.resetForHelper(
            self,
            spec
        )

        return
    end

    if spec.isDrumBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )

        self:stopVehicle()

        CombineBlockage.keepCombineTurnedOff(
            self
        )

        CombineBlockage.setBlockedCuttersTurnedOn(
            self,
            false
        )

        CombineBlockage.updateDisplayLoad(
            spec,
            dt
        )

        return
    end

    if spec.isFeederBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )

        CombineBlockage.keepCombineTurnedOff(
            self
        )

        CombineBlockage.updateDisplayLoad(
            spec,
            dt
        )

        return
    end

    if spec.isBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )

        CombineBlockage.setBlockedCuttersTurnedOn(
            self,
            false
        )

        CombineBlockage.updateDisplayLoad(
            spec,
            dt
        )

        return
    end

    if not self.isServer then
        CombineBlockage.updateDisplayLoad(spec, dt)
        return
    end

    local speedKmh = self:getLastSpeed()

    local intakeTarget =
        CombineBlockage.getCropCoverage(
            self
        )

    local intakeStep =
        dt
        * 0.001
        * CombineBlockage.INTAKE_RAMP_PER_SECOND


    if spec.cropIntake < intakeTarget then

        spec.cropIntake =
            math.min(
                intakeTarget,
                spec.cropIntake + intakeStep
            )

    else

        spec.cropIntake =
            math.max(
                intakeTarget,
                spec.cropIntake - intakeStep
            )
    end

    local isCutterTurnedOn =
        CombineBlockage.getIsAttachedCutterTurnedOn(
            self
        )

    if not isCutterTurnedOn then

        spec.headerLoad = 0
        spec.displayLoad = 0
        spec.cropIntake = 0

        spec.drumEventArmed = true
        spec.feederEventArmed = true

        if math.abs(spec.lastSentHeaderLoad) >= 0.5 then
            spec.lastSentHeaderLoad = 0
            CombineBlockage.raiseDirtyFlag(self)
        end

        return
    end

    spec.headerLoad =
        math.max(
            spec.headerLoad,
            CombineBlockage.IDLE_CUTTER_LOAD
        )

    local hasCropContact =
        isCutterTurnedOn
        and intakeTarget > 0.01
        and CombineBlockage.hasLoweredAttachedCutter(
            self
        )

    if not hasCropContact then

        spec.headerLoad =
            math.max(
                CombineBlockage.IDLE_CUTTER_LOAD,

                spec.headerLoad
                    - dt
                    * 0.001
                    * CombineBlockage.LOAD_FALL_PER_SECOND
            )

    else

        local speedTargetLoad =
            CombineBlockage.getTargetLoadForSpeed(
                speedKmh
            )

        local cropCoverageLoad =
            math.max(
                CombineBlockage.IDLE_CUTTER_LOAD,
                spec.cropIntake * 100
            )

        local targetLoad =
            math.min(
                speedTargetLoad,
                cropCoverageLoad
            )

        if spec.headerLoad < targetLoad then

            local riseStep =
                dt
                * 0.001
                * CombineBlockage.LOAD_RISE_PER_SECOND
                * spec.cropIntake


            spec.headerLoad =
                math.min(
                    targetLoad,
                    spec.headerLoad + riseStep
                )

        else

            local fallStep =
                dt
                * 0.001
                * CombineBlockage.LOAD_FALL_PER_SECOND


            spec.headerLoad =
                math.max(
                    targetLoad,
                    spec.headerLoad - fallStep
                )
        end
    end

    if spec.headerLoad
        <= CombineBlockage.DRUM_REARM_LOAD then

        spec.drumEventArmed = true
    end

    if spec.headerLoad
        <= CombineBlockage.FEEDER_REARM_LOAD then

        spec.feederEventArmed = true
    end

    if hasCropContact
        and spec.feederEventArmed
        and not spec.isDrumBlocked
        and not spec.isBlocked
        and CombineBlockage.getIsCombineTurnedOn(self)
        and spec.headerLoad
            >= CombineBlockage.FEEDER_TRIGGER_LOAD then

        spec.feederEventArmed = false

        if math.random()
            <= CombineBlockage.FEEDER_BLOCKAGE_CHANCE then

            CombineBlockage.setFeederBlocked(
                self,
                true
            )

            return
        end
    end

    if hasCropContact
        and spec.drumEventArmed
        and not spec.isFeederBlocked
        and not spec.isBlocked
        and CombineBlockage.getIsCombineTurnedOn(self)
        and spec.headerLoad
            >= CombineBlockage.DRUM_TRIGGER_LOAD then

        spec.drumEventArmed = false

        if math.random()
            <= CombineBlockage.DRUM_BLOCKAGE_CHANCE then

            CombineBlockage.setDrumBlocked(
                self,
                true
            )

            return
        end
    end

    if not spec.isDrumBlocked
        and not spec.isFeederBlocked
        and spec.headerLoad >= 100
        and math.floor(speedKmh + 0.5)
            >= CombineBlockage.BLOCK_SPEED_KMH then

        CombineBlockage.setBlocked(
            self,
            true
        )

        return
    end

    CombineBlockage.updateDisplayLoad(
        spec,
        dt
    )

    if math.abs(spec.headerLoad - spec.lastSentHeaderLoad) >= 0.5 then
        spec.lastSentHeaderLoad = spec.headerLoad
        CombineBlockage.raiseDirtyFlag(self)
    end
end

function CombineBlockage.getIsHelperActive(self)

    return self.getIsAIActive ~= nil
        and self:getIsAIActive()
end

function CombineBlockage.getIsCombineTurnedOn(self)

    return self.getIsTurnedOn == nil
        or self:getIsTurnedOn()
end

function CombineBlockage.keepCombineTurnedOff(self)

    if self.getIsTurnedOn ~= nil
        and self.setIsTurnedOn ~= nil
        and self:getIsTurnedOn() then

        self:setIsTurnedOn(false)
    end
end

function CombineBlockage.updateFeederClearInput(
    self,
    spec,
    isActiveForInputIgnoreSelection
)

    local isPressed = false

    if spec.isFeederBlocked
        and isActiveForInputIgnoreSelection
        and Input ~= nil
        and Input.isKeyPressed ~= nil
        and Input.KEY_lalt ~= nil
        and Input.KEY_s ~= nil then

        isPressed =
            Input.isKeyPressed(
                Input.KEY_lalt
            )
            and Input.isKeyPressed(
                Input.KEY_s
            )
    end

    if isPressed
        and not spec.feederClearKeyWasDown then

        CombineBlockage.requestClear(self, 3)
    end

    spec.feederClearKeyWasDown =
        isPressed
end

function CombineBlockage.resetForHelper(
    self,
    spec
)
    if spec.isBlocked then

        CombineBlockage.restoreBlockedCutters(
            self,
            spec
        )
    end

    if spec.isFeederBlocked
        and spec.feederCombineWasTurnedOn
        and self.setIsTurnedOn ~= nil then

        self:setIsTurnedOn(true)
    end

    spec.isBlocked = false
    spec.isDrumBlocked = false
    spec.isFeederBlocked = false

    spec.drumEventArmed = true
    spec.feederEventArmed = true

    spec.headerLoad = 0
    spec.displayLoad = 0
    spec.cropIntake = 0

    spec.clearBindingText = nil
    spec.clearDrumBindingText = nil

    spec.feederClearKeyWasDown = false
    spec.feederCombineWasTurnedOn = nil

    spec.blockedCutterStates = nil

    CombineBlockage.raiseDirtyFlag(self)

    if self.isClient then

        local headerActionEvent =
            spec.actionEvents[
                InputAction.COMBINEBLOCKAGE_CLEAR
            ]

        if headerActionEvent ~= nil then

            g_inputBinding:setActionEventActive(
                headerActionEvent.actionEventId,
                false
            )
        end


        local drumActionEvent =
            spec.actionEvents[
                InputAction.COMBINEBLOCKAGE_CLEAR_DRUM
            ]

        if drumActionEvent ~= nil then

            g_inputBinding:setActionEventActive(
                drumActionEvent.actionEventId,
                false
            )
        end
    end
end

function CombineBlockage.setBlockedCuttersTurnedOn(
    self,
    isTurnedOn
)

    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters


    if cutters == nil then
        return
    end


    for cutter, _ in pairs(cutters) do

        if cutter.setIsTurnedOn ~= nil then

            if not isTurnedOn
                or cutter.getCanBeTurnedOn == nil
                or cutter:getCanBeTurnedOn() then

                cutter:setIsTurnedOn(
                    isTurnedOn
                )
            end
        end
    end
end

function CombineBlockage.captureAndStopCutters(
    self,
    spec
)

    spec.blockedCutterStates = {}


    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters


    if cutters == nil then
        return
    end


    for cutter, _ in pairs(cutters) do

        if cutter.setIsTurnedOn ~= nil
            and cutter.getIsTurnedOn ~= nil then

            spec.blockedCutterStates[cutter] =
                cutter:getIsTurnedOn()

            cutter:setIsTurnedOn(false)
        end
    end
end

function CombineBlockage.restoreBlockedCutters(
    self,
    spec
)

    if spec.blockedCutterStates == nil then
        return
    end


    local combineSpec =
        self.spec_combine

    local attachedCutters =
        combineSpec
        and combineSpec.attachedCutters


    if attachedCutters ~= nil then

        for cutter, wasTurnedOn
            in pairs(spec.blockedCutterStates) do

            if wasTurnedOn
                and attachedCutters[cutter] ~= nil
                and cutter.setIsTurnedOn ~= nil
                and (
                    cutter.getCanBeTurnedOn == nil
                    or cutter:getCanBeTurnedOn()
                ) then

                cutter:setIsTurnedOn(true)
            end
        end
    end


    spec.blockedCutterStates = nil
end

function CombineBlockage.getIsAttachedCutterTurnedOn(
    self
)

    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters

    if cutters == nil then

        return self.getIsTurnedOn ~= nil
            and self:getIsTurnedOn()
    end


    local foundReadableCutter = false

    for cutter, _ in pairs(cutters) do

        if cutter.getIsTurnedOn ~= nil then

            foundReadableCutter = true

            if cutter:getIsTurnedOn() then
                return true
            end
        end
    end

    return
        not foundReadableCutter
        and self.getIsTurnedOn ~= nil
        and self:getIsTurnedOn()
end

function CombineBlockage.updateDisplayLoad(
    spec,
    dt
)

    local currentDisplayLoad =
        spec.displayLoad
        or spec.headerLoad


    local alpha =
        1
        - math.exp(
            -dt
            * 0.001
            * CombineBlockage.DISPLAY_SMOOTHING_SPEED
        )


    spec.displayLoad =
        currentDisplayLoad
        + (
            spec.headerLoad
            - currentDisplayLoad
        )
        * alpha


    if math.abs(
        spec.headerLoad
        - spec.displayLoad
    ) < 0.01 then

        spec.displayLoad =
            spec.headerLoad
    end
end

function CombineBlockage.disableCruiseControl(self)

    if self.setCruiseControlState ~= nil
        and self.getCruiseControlState ~= nil
        and self:getCruiseControlState()
            ~= Drivable.CRUISECONTROL_STATE_OFF then

        self:setCruiseControlState(
            Drivable.CRUISECONTROL_STATE_OFF
        )
    end
end

function CombineBlockage.getTargetLoadForSpeed(
    speedKmh
)

    local speed =
        math.max(
            0,
            speedKmh
        )

    if speed
        <= CombineBlockage.NORMAL_ZONE_END_SPEED_KMH then

        local normalFactor =
            speed
            / CombineBlockage.NORMAL_ZONE_END_SPEED_KMH


        return
            CombineBlockage.IDLE_CUTTER_LOAD
            + (
                CombineBlockage.NORMAL_ZONE_END_LOAD
                - CombineBlockage.IDLE_CUTTER_LOAD
            )
            * normalFactor
    end

    local redSpeedRange =
        CombineBlockage.FULL_LOAD_SPEED_KMH
        - CombineBlockage.NORMAL_ZONE_END_SPEED_KMH


    local redFactor =
        math.min(
            1,
            (
                speed
                - CombineBlockage.NORMAL_ZONE_END_SPEED_KMH
            )
            / redSpeedRange
        )


    return
        CombineBlockage.NORMAL_ZONE_END_LOAD
        + (
            100
            - CombineBlockage.NORMAL_ZONE_END_LOAD
        )
        * redFactor
end

function CombineBlockage.getCropCoverage(
    self
)

    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters


    if cutters == nil then
        return 0
    end


    local coverageSum = 0
    local cutterCount = 0


    for cutter, _ in pairs(cutters) do

        local coverage = 0

        if cutter.getTestAreaChargeByWorkAreaIndex ~= nil then

            coverage =
                cutter:getTestAreaChargeByWorkAreaIndex(
                    1
                )

        elseif cutter.spec_cutter ~= nil
            and cutter.spec_cutter.cutterLoad ~= nil then

            coverage =
                cutter.spec_cutter.cutterLoad

        elseif cutter.getCutterLoad ~= nil then

            coverage =
                cutter:getCutterLoad()
        end


        coverageSum =
            coverageSum
            + math.min(
                1,
                math.max(
                    0,
                    coverage
                )
            )


        cutterCount =
            cutterCount + 1
    end


    if cutterCount == 0 then
        return 0
    end


    return math.min(
        1,
        math.max(
            0,
            coverageSum / cutterCount
        )
    )
end

function CombineBlockage.hasAttachedCutter(
    self
)

    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters


    return cutters ~= nil
        and next(cutters) ~= nil
end

function CombineBlockage.hasLoweredAttachedCutter(
    self
)

    local combineSpec =
        self.spec_combine

    local cutters =
        combineSpec
        and combineSpec.attachedCutters


    if cutters == nil then
        return true
    end


    local hasCutter = false


    for cutter, _ in pairs(cutters) do

        hasCutter = true


        if cutter.getIsLowered == nil
            or cutter:getIsLowered(true) then

            return true
        end
    end


    return not hasCutter
end

function CombineBlockage:onDraw(
    isActiveForInput,
    isActiveForInputIgnoreSelection,
    isSelected
)
    if not isActiveForInputIgnoreSelection then
        return
    end

    if CombineBlockage.getIsHelperActive(self) then
        return
    end


    local spec =
        self.spec_combineBlockage

    if spec.isBlocked
        or spec.isDrumBlocked
        or spec.isFeederBlocked then

        CombineBlockage.drawBlockedWarning(
            spec
        )
    end

    if not CombineBlockage.hasAttachedCutter(
        self
    ) then

        return
    end

    local load =
        spec.displayLoad
        or spec.headerLoad


    local loadState =
        g_i18n:getText(
            "hud_combineBlockage_stateNormal"
        )


    if load
        > CombineBlockage.NORMAL_ZONE_END_LOAD then

        loadState =
            g_i18n:getText(
                "hud_combineBlockage_stateHigh"
            )
    end

    local x = 0.420
    local y = 0.925

    local width = 0.160
    local height = 0.032


    local barX =
        x + 0.004

    local barY =
        y + 0.007


    local barWidth =
        width - 0.008

    local barHeight =
        0.006

    local normalWidth =
        barWidth
        * CombineBlockage.NORMAL_ZONE_END_LOAD
        * 0.01


    local highWidth =
        barWidth - normalWidth

    local markerX =
        barX
        + barWidth
        * math.min(
            1,
            math.max(
                0,
                load * 0.01
            )
        )

    setTextAlignment(
        RenderText.ALIGN_LEFT
    )

    setTextBold(true)

    setTextColor(
        1,
        1,
        1,
        1
    )


    renderText(
        x + 0.004,
        y + 0.019,
        0.0105,
        string.format(
            g_i18n:getText(
                "hud_combineBlockage_load"
            ),
            math.floor(
                load + 0.5
            ),
            loadState
        )
    )
    drawFilledRect(
        barX,
        barY,
        barWidth,
        barHeight,
        0.05,
        0.05,
        0.05,
        0.75
    )
    drawFilledRect(
        barX,
        barY,
        normalWidth,
        barHeight,
        0.08,
        0.46,
        0.10,
        0.90
    )
    drawFilledRect(
        barX + normalWidth,
        barY,
        highWidth,
        barHeight,
        0.72,
        0.04,
        0.03,
        0.95
    )
    drawFilledRect(
        math.min(
            barX
                + barWidth
                - 0.0015,

            math.max(
                barX,
                markerX
                    - 0.00075
            )
        ),

        barY - 0.002,
        0.0015,
        barHeight + 0.004,

        1,
        1,
        1,
        0.95
    )
    setTextBold(false)

    setTextAlignment(
        RenderText.ALIGN_LEFT
    )

    setTextColor(
        1,
        1,
        1,
        1
    )
end

function CombineBlockage.drawBlockedWarning(
    spec
)

    local titleText
    local hintText

    if spec.isFeederBlocked then

        titleText =
            g_i18n:getText(
                "warning_combineBlockage_feederBlockedPersistent"
            )

        hintText =
            g_i18n:getText(
                "warning_combineBlockage_feederClearHint"
            )

    else

        local isDrumBlocked =
            spec.isDrumBlocked


        local bindingText =
            isDrumBlocked
            and (
                spec.clearDrumBindingText
                or CombineBlockage.getDrumClearBindingText()
            )
            or (
                spec.clearBindingText
                or CombineBlockage.getClearBindingText()
            )


        local titleKey =
            isDrumBlocked
            and "warning_combineBlockage_drumBlockedPersistent"
            or "warning_combineBlockage_headerBlockedPersistent"


        titleText =
            g_i18n:getText(
                titleKey
            )


        hintText =
            string.format(
                g_i18n:getText(
                    "warning_combineBlockage_clearHint"
                ),
                bindingText
            )
    end

    local panelX = 0.30
    local panelY = 0.465

    local panelWidth = 0.40
    local panelHeight = 0.075

    drawFilledRect(
        panelX,
        panelY,
        panelWidth,
        panelHeight,

        0.06,
        0.005,
        0.005,
        0.84
    )
    drawFilledRect(
        panelX,
        panelY
            + panelHeight
            - 0.003,

        panelWidth,
        0.003,

        0.85,
        0.03,
        0.02,
        1
    )
    drawFilledRect(
        panelX,
        panelY,
        panelWidth,
        0.003,

        0.85,
        0.03,
        0.02,
        1
    )
    setTextAlignment(
        RenderText.ALIGN_CENTER
    )

    setTextBold(true)

    setTextColor(
        1.00,
        0.10,
        0.06,
        1
    )


    renderText(
        0.50,
        panelY + 0.043,
        0.021,
        titleText
    )
    setTextColor(
        1,
        1,
        1,
        1
    )


    renderText(
        0.50,
        panelY + 0.017,
        0.0125,
        hintText
    )

    setTextBold(false)

    setTextAlignment(
        RenderText.ALIGN_LEFT
    )

    setTextColor(
        1,
        1,
        1,
        1
    )
end

function CombineBlockage:getCanMotorRun(
    superFunc
)

    return superFunc(self)
end

function CombineBlockage:onRegisterActionEvents(
    isActiveForInput,
    isActiveForInputIgnoreSelection
)

    if not self.isClient then
        return
    end


    local spec =
        self.spec_combineBlockage

    self:clearActionEventsTable(
        spec.actionEvents
    )
    if isActiveForInputIgnoreSelection then

        local _, actionEventId =
            self:addActionEvent(
                spec.actionEvents,
                InputAction.COMBINEBLOCKAGE_CLEAR,
                self,
                CombineBlockage.actionEventClear,
                false,
                true,
                false,
                true,
                nil
            )


        if actionEventId ~= nil then
            g_inputBinding:setActionEventText(
                actionEventId,
                g_i18n:getText(
                    "action_combineBlockage_clearHeader"
                )
            )

            g_inputBinding:setActionEventTextPriority(
                actionEventId,
                GS_PRIO_VERY_HIGH
            )

            g_inputBinding:setActionEventActive(
                actionEventId,
                spec.isBlocked
            )
        end
        local _, drumActionEventId =
            self:addActionEvent(
                spec.actionEvents,
                InputAction.COMBINEBLOCKAGE_CLEAR_DRUM,
                self,
                CombineBlockage.actionEventClearDrum,
                false,
                true,
                false,
                true,
                nil
            )


        if drumActionEventId ~= nil then
            g_inputBinding:setActionEventText(
                drumActionEventId,
                g_i18n:getText(
                    "action_combineBlockage_clearDrum"
                )
            )

            g_inputBinding:setActionEventTextPriority(
                drumActionEventId,
                GS_PRIO_VERY_HIGH
            )

            g_inputBinding:setActionEventActive(
                drumActionEventId,
                spec.isDrumBlocked
            )
        end
    end
end

function CombineBlockage.actionEventClear(
    self,
    actionName,
    inputValue,
    callbackState,
    isAnalog
)

    if self.spec_combineBlockage.isBlocked then

        CombineBlockage.requestClear(self, 1)
    end
end

function CombineBlockage.actionEventClearDrum(
    self,
    actionName,
    inputValue,
    callbackState,
    isAnalog
)

    if self.spec_combineBlockage.isDrumBlocked then

        CombineBlockage.requestClear(self, 2)
    end
end

function CombineBlockage.getBindingText(
    actionName,
    fallbackTextKey
)

    local fallbackText =
        g_i18n:getText(
            fallbackTextKey
        )


    if g_inputDisplayManager == nil
        or g_inputDisplayManager.getControllerSymbolOverlays == nil then

        return fallbackText
    end


    local success, helpElement =
        pcall(
            g_inputDisplayManager.getControllerSymbolOverlays,
            g_inputDisplayManager,
            actionName,
            "",
            "",
            false
        )


    if success
        and helpElement ~= nil
        and helpElement.keys ~= nil
        and #helpElement.keys > 0 then

        return table.concat(
            helpElement.keys,
            " + "
        )
    end


    return fallbackText
end

function CombineBlockage.getClearBindingText()

    return CombineBlockage.getBindingText(
        InputAction.COMBINEBLOCKAGE_CLEAR,
        "action_combineBlockage_clearHeader"
    )
end

function CombineBlockage.getDrumClearBindingText()

    return CombineBlockage.getBindingText(
        InputAction.COMBINEBLOCKAGE_CLEAR_DRUM,
        "action_combineBlockage_clearDrum"
    )
end

function CombineBlockage.setBlocked(
    self,
    isBlocked
)

    local spec =
        self.spec_combineBlockage

    if spec.isBlocked == isBlocked then
        return
    end

    if isBlocked
        and (
            spec.isDrumBlocked
            or spec.isFeederBlocked
        ) then

        return
    end


    spec.isBlocked =
        isBlocked

    CombineBlockage.raiseDirtyFlag(self)

    if self.isClient then

        spec.clearBindingText =
            isBlocked
            and CombineBlockage.getClearBindingText()
            or nil
    end

    if isBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )
        CombineBlockage.captureAndStopCutters(
            self,
            spec
        )
    else

        spec.headerLoad = 0
        spec.displayLoad = 0
        spec.cropIntake = 0

        spec.drumEventArmed = true
        spec.feederEventArmed = true

        CombineBlockage.restoreBlockedCutters(
            self,
            spec
        )
    end

    if self.isClient
        and not isBlocked then

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,

            g_i18n:getText(
                "warning_combineBlockage_headerCleared"
            )
        )
    end

    local actionEvent =
        spec.actionEvents[
            InputAction.COMBINEBLOCKAGE_CLEAR
        ]


    if actionEvent ~= nil then

        g_inputBinding:setActionEventActive(
            actionEvent.actionEventId,
            isBlocked
        )
    end
end

function CombineBlockage.setDrumBlocked(
    self,
    isBlocked
)

    local spec =
        self.spec_combineBlockage

    if spec.isDrumBlocked == isBlocked then
        return
    end

    if isBlocked
        and (
            spec.isBlocked
            or spec.isFeederBlocked
        ) then

        return
    end


    spec.isDrumBlocked =
        isBlocked

    CombineBlockage.raiseDirtyFlag(self)

    if self.isClient then

        spec.clearDrumBindingText =
            isBlocked
            and CombineBlockage.getDrumClearBindingText()
            or nil
    end

    if isBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )
        self:stopVehicle()

        CombineBlockage.keepCombineTurnedOff(
            self
        )
        CombineBlockage.setBlockedCuttersTurnedOn(
            self,
            false
        )
    else

        spec.headerLoad = 0
        spec.displayLoad = 0
        spec.cropIntake = 0

        spec.drumEventArmed = true
        spec.feederEventArmed = true
    end

    if self.isClient
        and not isBlocked then

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,

            g_i18n:getText(
                "warning_combineBlockage_drumCleared"
            )
        )
    end

    local actionEvent =
        spec.actionEvents[
            InputAction.COMBINEBLOCKAGE_CLEAR_DRUM
        ]


    if actionEvent ~= nil then

        g_inputBinding:setActionEventActive(
            actionEvent.actionEventId,
            isBlocked
        )
    end
end

function CombineBlockage.setFeederBlocked(
    self,
    isBlocked
)

    local spec =
        self.spec_combineBlockage

    if spec.isFeederBlocked == isBlocked then
        return
    end

    if isBlocked
        and (
            spec.isBlocked
            or spec.isDrumBlocked
        ) then

        return
    end


    spec.isFeederBlocked =
        isBlocked

    CombineBlockage.raiseDirtyFlag(self)

    if isBlocked then

        CombineBlockage.disableCruiseControl(
            self
        )
        spec.feederCombineWasTurnedOn =
            CombineBlockage.getIsCombineTurnedOn(
                self
            )
        CombineBlockage.keepCombineTurnedOff(
            self
        )
    else
        spec.headerLoad = 0
        spec.displayLoad = 0
        spec.cropIntake = 0

        spec.drumEventArmed = true

        spec.feederEventArmed = false

        spec.feederClearKeyWasDown = true

        spec.feederCombineWasTurnedOn = nil
    end

    if self.isClient
        and not isBlocked then

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,

            g_i18n:getText(
                "warning_combineBlockage_feederCleared"
            )
        )
    end
end

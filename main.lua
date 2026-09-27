local SCREEN = "BabycarePrototype"
local ZELDA_SCREEN = "BabycareZelda"
local Font = require("src.render.Font")
local Assets = require("src.render.Assets")
local GbcPalette = require("src.render.GbcPalette")
local Chrome = require("src.ui.gen2.Chrome")
local Bag = require("src.inventory.Bag")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local Palettes = require("src.world.gen2.Palettes")
local Breeding = require("src.core.gen2.Breeding")
local Clock = require("src.core.gen2.Clock")
local Mail = require("src.core.gen2.Mail")
local Boxes = require("src.core.gen2.Boxes")
local OverworldController = require("src.world.OverworldController")
local TextBox = require("src.render.TextBox")
local PackMenu = require("src.ui.gen2.PackMenu")
local Screens = require("src.ui.Screens")
local Sprites = require("src.pokemon.Sprites")
local Mon = require("src.battle.gen2.Mon")
local MonAnim = require("src.render.MonAnim")
local EggHatchAnim = require("src.ui.gen2.EggHatchAnim")
local Gen2World = require("src.world.gen2.World")
local Game = require("src.core.Game")

local BABY_MONITOR_ID = "BABY_MONITOR"

return function(mod)
  -- The Baby Monitor is a real Crystal PACK item.  Gen 2's public item
  -- schema carries the cross-generation fields; the Gen 2-only pocket/menu
  -- attributes are applied to the live record once game.ready provides it.
  mod.content.items:register(BABY_MONITOR_ID, {
    id = BABY_MONITOR_ID,
    name = "BABY MONITOR",
    price = 0,
    tossable = false,
  })

  -- Nudge the egg-crack sprite cluster down 4 pixels in the hatch cutscene so
  -- the shell break lines sit lower on the egg, matching the Nursery mockup.
  -- This patches only the crack object placement; the rest of Crystal's hatch
  -- timing, wobble, fragments and mon reveal remain untouched.
  function EggHatchAnim:crackShell(round)
    local a = (round - 1) % 8
    if a == 7 then return end
    if a % 2 == 0 then return end
    local step = math.floor(a / 2)
    self.sprites[#self.sprites + 1] = {
      kind = "crack",
      x = 11 * 8,
      y = step * 8 + 9 * 8 + 4,
    }
    self:playSfx("Sfx_EggCrack")
  end

  local function vanillaPages(pages)
    local out = {}
    for _, page in ipairs(pages or {}) do
      if type(page) == "table" then
        local a = tostring(page[1] or "")
        local b = tostring(page[2] or "")
        if b ~= "" then out[#out + 1] = a .. "\n" .. b else out[#out + 1] = a end
      else
        out[#out + 1] = tostring(page or "")
      end
    end
    return table.concat(out, "\f")
  end

  local function zeldaPagesNoScroll(pages)
    -- Zelda's Nursery dialogue should behave like deliberately paged Crystal
    -- dialogue: at most two visible lines, then wait for A/B.  TextBox normally
    -- soft-wraps an overlong authored line; if that creates a third line it
    -- performs ScrollTextUpOneLine, which looks like dialogue auto-scrolling.
    --
    -- Pre-paginate each authored Zelda page, then turn every two wrapped lines
    -- into an explicit form-feed page.  Re-pagination is stable because every
    -- emitted line already fits the current textbox width.
    local out = {}
    for _, page in ipairs(pages or {}) do
      local raw
      if type(page) == "table" then
        local a = tostring(page[1] or "")
        local b = tostring(page[2] or "")
        raw = b ~= "" and (a .. "\n" .. b) or a
      else
        raw = tostring(page or "")
      end

      local wrapped = TextBox.paginate(raw)
      for _, wrappedPage in ipairs(wrapped or {}) do
        local i = 1
        while i <= #wrappedPage do
          local a = tostring(wrappedPage[i] or "")
          local b = tostring(wrappedPage[i + 1] or "")
          out[#out + 1] = b ~= "" and (a .. "\n" .. b) or a
          i = i + 2
        end
      end
    end
    if #out == 0 then out[1] = "" end
    return table.concat(out, "\f")
  end

  local HEART_X = {
    hunger = { 30, 38, 46, 54 },
    fun    = { 74, 82, 90, 98 },
    clean  = { 117, 125, 133, 141 },
  }
  local HEART_Y = 16

  -- Bottom bar, left to right:
  -- FOOD, PLAY, CLEAN, MEDICINE, LIGHTS, CARE, CALL, ZELDA.
  local SELECTOR_POS = {
    { 7, 120 },
    { 23, 120 },
    { 39, 120 },
    { 55, 120 },
    { 71, 120 },
    { 87, 120 },
    { 103, 120 },
    { 135, 120 },
  }

  -- A small first-pass food pool made only from vanilla Crystal items that
  -- make sense as actual nursery food/drink.  Status berries, powders and
  -- potions are intentionally left for the MEDICINE menu instead.
  local FOOD_DEFS = {
    -- digestion is a fraction of one full hidden digestion meter.  Meals span
    -- the requested 20%-35% range, with lighter fruit/water at the low end and
    -- the dense RageCandyBar at the top.
    { id = "BERRY",         label = "BERRY",          hunger = 0.5, digestion = 0.20, anim = "berry" },
    { id = "BERRY_JUICE",   label = "BERRY JUICE",    hunger = 1.0, digestion = 0.22, anim = "berry_juice" },
    { id = "FRESH_WATER",   label = "FRESH WATER",    hunger = 0.5, digestion = 0.20, anim = "fresh_water" },
    { id = "SODA_POP",      label = "SODA POP",       hunger = 1.0, digestion = 0.25, anim = "soda_pop" },
    { id = "LEMONADE",      label = "LEMONADE",       hunger = 1.5, digestion = 0.27, anim = "lemonade" },
    { id = "MOOMOO_MILK",   label = "MOOMOO MILK",    hunger = 1.5, digestion = 0.30, anim = "moomoo_milk" },
    { id = "RAGECANDYBAR",  label = "RAGECANDYBAR",   hunger = 1.0, digestion = 0.35, anim = "ragecandybar" },
  }


  local FOOD_DIET_STRAIN = {
    BERRY = 0.02,
    BERRY_JUICE = 0.04,
    FRESH_WATER = 0.00,
    SODA_POP = 0.10,
    LEMONADE = 0.12,
    MOOMOO_MILK = 0.18,
    RAGECANDYBAR = 0.24,
  }

  local MEDICINE_DEFS = {
    { id = "ANTIDOTE",    label = "ANTIDOTE",    cures = "tummyache", asset = "antidote" },
    { id = "AWAKENING",   label = "AWAKENING",   cures = "tired",     asset = "awakening" },
    { id = "BURN_HEAL",   label = "BURN HEAL",   cures = "rash",      asset = "burn_heal" },
    { id = "ICE_HEAL",    label = "ICE HEAL",    cures = "feverish",  asset = "ice_heal" },
    { id = "PARLYZ_HEAL", label = "PARLYZ HEAL", cures = "famished",  asset = "parlyz_heal" },
    { id = "FULL_HEAL",   label = "FULL HEAL",   cures = "any",       asset = "full_heal" },
  }

  local SICKNESS_KINDS = { "tummyache", "tired", "rash", "feverish", "famished" }
  local SICKNESS_LABELS = {
    tummyache = "TUMMYACHE",
    tired = "TIRED",
    rash = "RASH",
    feverish = "FEVERISH",
    famished = "SAPPED",
  }
  local SICKNESS_THOUGHTS = {
    tummyache = "sick",
    tired = "exhausted",
    rash = "sick",
    feverish = "worried",
    famished = "sick",
  }

  -- The wandering animation is intentionally discrete.  There is no tweening
  -- between these authored positions: one pose/position simply replaces the
  -- last every 0.60 seconds, like the original Tamagotchi presentation.
  local BABY_STEP_SECONDS = 0.60
  local BABY_WALK = {
    { frame = 1, x = 52,  y = 52, flip = false },
    { frame = 2, x = 32,  y = 45, flip = false },
    { frame = 1, x = 10,  y = 52, flip = false },
    { frame = 2, x = -10, y = 45, flip = false },
    { frame = 1, x = 9,   y = 52, flip = true  },
    { frame = 2, x = 33,  y = 45, flip = true  },
    { frame = 1, x = 51,  y = 52, flip = true  },
    { frame = 2, x = 73,  y = 45, flip = true  },
    { frame = 1, x = 95,  y = 52, flip = true  },
    { frame = 2, x = 115, y = 45, flip = true  },
    { frame = 1, x = 94,  y = 52, flip = false },
    { frame = 2, x = 72,  y = 45, flip = false },
    { frame = 1, x = 52,  y = 52, flip = false },
  }

  -- Never make a newly opened nursery look as though the baby teleported back
  -- to its starting mark.  Pick from authored non-centre walk positions so a
  -- fresh check-in looks like we caught the babymon wherever it happened to be.
  local BABY_RANDOM_STARTS = { 2, 3, 4, 5, 6, 8, 9, 10, 11, 12 }


  -- Species-specific Nursery movement. The shared walk path still keeps every
  -- baby inside the authored room bounds, but cadence and idle flourishes make
  -- each species feel less interchangeable. Flourishes are deliberately rare:
  -- a baby may stop to look around, hop, turn its back, or occasionally do a
  -- playful 90-degree-step cartwheel before returning to its walk.
  local MOVEMENT_PROFILES = {
    PICHU     = { stepScale = 0.85, flourishChance = 0.040, turn = 2, hop = 4, back = 1, cartwheel = 2 },
    CLEFFA    = { stepScale = 1.15, flourishChance = 0.030, turn = 5, hop = 2, back = 3, cartwheel = 0 },
    IGGLYBUFF = { stepScale = 1.05, flourishChance = 0.035, turn = 3, hop = 5, back = 1, cartwheel = 1 },
    TOGEPI    = { stepScale = 1.20, flourishChance = 0.028, turn = 4, hop = 1, back = 4, cartwheel = 0 },
    TYROGUE   = { stepScale = 0.90, flourishChance = 0.042, turn = 2, hop = 4, back = 2, cartwheel = 3 },
    SMOOCHUM  = { stepScale = 1.10, flourishChance = 0.030, turn = 5, hop = 1, back = 4, cartwheel = 0 },
    ELEKID    = { stepScale = 0.80, flourishChance = 0.050, turn = 2, hop = 4, back = 1, cartwheel = 4 },
    MAGBY     = { stepScale = 0.95, flourishChance = 0.040, turn = 3, hop = 3, back = 3, cartwheel = 2 },
    MIKON     = { stepScale = 0.95, flourishChance = 0.038, turn = 4, hop = 2, back = 3, cartwheel = 1 },
    MONJA     = { stepScale = 1.18, flourishChance = 0.026, turn = 4, hop = 1, back = 4, cartwheel = 0 },
    GYOPIN    = { stepScale = 1.05, flourishChance = 0.034, turn = 3, hop = 4, back = 2, cartwheel = 1 },
    PARA      = { stepScale = 1.10, flourishChance = 0.032, turn = 5, hop = 2, back = 3, cartwheel = 0 },
    HINAZU    = { stepScale = 0.82, flourishChance = 0.048, turn = 2, hop = 5, back = 1, cartwheel = 3 },
    KONYA     = { stepScale = 0.88, flourishChance = 0.045, turn = 5, hop = 3, back = 2, cartwheel = 2 },
    PUCHIKON  = { stepScale = 0.92, flourishChance = 0.042, turn = 3, hop = 4, back = 2, cartwheel = 2 },
    BETOBEBI  = { stepScale = 1.25, flourishChance = 0.024, turn = 4, hop = 1, back = 5, cartwheel = 0 },
    PUDI      = { stepScale = 0.86, flourishChance = 0.046, turn = 3, hop = 4, back = 2, cartwheel = 3 },
    BARIRINA  = { stepScale = 1.12, flourishChance = 0.030, turn = 5, hop = 2, back = 4, cartwheel = 0 },
    TSUINZU   = { stepScale = 1.00, flourishChance = 0.036, turn = 4, hop = 2, back = 5, cartwheel = 1 },
  }
  local MOVEMENT_DEFAULT = { stepScale = 1.0, flourishChance = 0.030, turn = 3, hop = 2, back = 2, cartwheel = 1 }
  local MOVEMENT_TURN_SECONDS = 0.22
  local MOVEMENT_HOP_SECONDS = 0.14
  local MOVEMENT_BACK_SECONDS = 0.28
  local MOVEMENT_CARTWHEEL_SECONDS = 0.12

  local REFUSE_STEP_SECONDS = 0.60
  local FULL_HUNGER_REFUSE = {
    -- Three complete left/right "no" shakes in place.  Horizontal mirroring
    -- is the turn; alternating the two supplied idle frames keeps the same
    -- chunky Tamagotchi cadence as the rest of the nursery.
    { frame = 1, x = 52, y = 52, flip = false },
    { frame = 2, x = 52, y = 52, flip = true  },
    { frame = 1, x = 52, y = 52, flip = false },
    { frame = 2, x = 52, y = 52, flip = true  },
    { frame = 1, x = 52, y = 52, flip = false },
    { frame = 2, x = 52, y = 52, flip = true  },
    { frame = 1, x = 52, y = 52, flip = false },
  }

  -- Reconstructed directly from the supplied feeding GIF.  The baby stays in
  -- the center and alternates its two authored poses while the berry advances
  -- full -> partly eaten -> mostly eaten -> gone, one hard frame every .60s.
  local EAT_STEP_SECONDS = 0.60
  local BERRY_EAT = {
    { frame = 2, x = 52, y = 52, berry = 1 },
    { frame = 1, x = 51, y = 52, berry = 1 },
    { frame = 2, x = 52, y = 52, berry = 2 },
    { frame = 1, x = 51, y = 52, berry = 2 },
    { frame = 2, x = 52, y = 52, berry = 3 },
    { frame = 1, x = 51, y = 52, berry = 3 },
    { frame = 2, x = 52, y = 52, berry = nil },
  }

  local GENERIC_EAT = {
    { frame = 2, x = 52, y = 52 },
    { frame = 1, x = 51, y = 52 },
    { frame = 2, x = 52, y = 52 },
    { frame = 1, x = 51, y = 52 },
  }

  -- Clean / waste system. Each poop immediately costs one full Clean heart,
  -- then continues to contribute to gradual filth while it remains. Multiple
  -- piles stack their exposure, up to three at once. Digestion rises slowly on
  -- its own and gets a much larger push from FOOD.
  local WASTE_STEP_SECONDS = 0.60
  local WASTE_POSITIONS = {
    { 104, 90 },
    { 18, 90 },
    { 62, 94 },
  }
  local WASTE_MAX = 3
  local WASTE_CLEAN_DRAIN_SECONDS = 30 * 60 -- half a heart per pile / 30 real minutes
  local DIGESTION_FULL_SECONDS = 10 * 60 * 60 -- passive digestion fills in ~10 real hours
  local POOP_DELAY_MIN_SECONDS = 60
  local POOP_DELAY_MAX_SECONDS = 5 * 60
  local POOP_STEP_SECONDS = 0.18
  local POOP_SHAKE = { 0, -2, 2, -2, 2, -1, 1 }
  local CLEAN_STEP_SECONDS = 0.25
  local FLUSH_Y = 31
  local FLUSH_SWEEP = {
    { x = -4 },
    { x = 21 },
    { x = 47 },
    { x = 73 },
    { x = 99, clearsWaste = true },
    { x = 125 },
    { x = 151 },
  }

  -- PLAY is a proper Tamagotchi-style activity now.  All three games run
  -- directly in the Nursery room, use Mt. Moon Square's song while active and award
  -- one FUN heart for a full clear.  Thought bubbles are the shared visual
  -- reaction layer for PLAY and the rest of the care loop; authored reactions
  -- stay on screen for a full two seconds unless a later system explicitly
  -- replaces them with a higher-priority reaction.
  local PLAY_MENU_ITEMS = { "BOUNCE", "MATCH", "MEMORY" }
  local THOUGHT_SECONDS = 2.0
  local PLAY_RESULT_SECONDS = 2.0
  local PLAY_FUN_REWARD = 1.0
  local PLAY_FUN_REWARD_IMPERFECT = 0.5
  local PLAY_BABY_LANES = { 4, 52, 100 }
  local PLAY_BALL_TOP_Y = 32
  local PLAY_BALL_HIT_MIN_Y = 70
  local PLAY_BALL_HIT_MAX_Y = 90
  local PLAY_BALL_MISS_Y = 108
  local PLAY_BALL_FALL_SPEED_START = 38
  local PLAY_BALL_FALL_SPEED_END = 98
  local PLAY_BALL_RISE_SPEED = 92
  local PLAY_BOUNCE_START_DELAY = 0.85
  local PLAY_BOUNCE_BETWEEN_DELAY = 0.22
  local PLAY_BOUNCE_JUMP_SECONDS = 0.32
  local PLAY_MATCH_RESPONSE_SECONDS = 1.5
  local PLAY_MATCH_RESET_SECONDS = 0.40
  local PLAY_MATCH_WAIT_MIN_SECONDS = 1.0
  local PLAY_MATCH_WAIT_RANDOM_SECONDS = 4.0
  local PLAY_MATCH_TRICK_SECONDS = 0.25
  local PLAY_MATCH_CHORD_SECONDS = 0.22
  local PLAY_MEMORY_LENGTHS = { 2, 3, 3, 4, 4 }
  local PLAY_MEMORY_STEP_SECONDS = 0.75
  local PLAY_MEMORY_LINGER_SECONDS = 1.00
  local PLAY_MEMORY_BETWEEN_SECONDS = 0.55
  local PLAY_MEMORY_FLASH_SECONDS = 0.16
  local PLAY_DIRECTIONS = { "left", "up", "right", "down" }

  -- Species personality foundation. These are intentionally mild modifiers:
  -- every baby still follows the same core care rules, but favorite foods,
  -- favorite games, one disliked food, slightly different need rates, and a
  -- small bedtime tweak make each species feel distinct without turning care
  -- into eight separate rulebooks. Preferences are discovered through play.
  local PERSONALITY_PROFILES = {
    PICHU = {
      favoriteFood = "BERRY_JUICE", dislikedFood = "MOOMOO_MILK", favoriteGame = "MATCH",
      hungerRate = 1.05, funRate = 1.10, sleepStart = 22, sleepWake = 9,
    },
    CLEFFA = {
      favoriteFood = "MOOMOO_MILK", dislikedFood = "SODA_POP", favoriteGame = "MEMORY",
      hungerRate = 0.95, funRate = 0.95, sleepStart = 20, sleepWake = 9,
    },
    IGGLYBUFF = {
      favoriteFood = "BERRY", dislikedFood = "FRESH_WATER", favoriteGame = "BOUNCE",
      hungerRate = 1.00, funRate = 1.10, sleepStart = 21, sleepWake = 10,
    },
    TOGEPI = {
      favoriteFood = "BERRY", dislikedFood = "RAGECANDYBAR", favoriteGame = "MEMORY",
      hungerRate = 0.95, funRate = 1.00, sleepStart = 21, sleepWake = 9,
    },
    TYROGUE = {
      favoriteFood = "MOOMOO_MILK", dislikedFood = "LEMONADE", favoriteGame = "BOUNCE",
      hungerRate = 1.10, funRate = 1.05, sleepStart = 21, sleepWake = 8,
    },
    SMOOCHUM = {
      favoriteFood = "LEMONADE", dislikedFood = "RAGECANDYBAR", favoriteGame = "MATCH",
      hungerRate = 1.00, funRate = 1.05, sleepStart = 21, sleepWake = 9,
    },
    ELEKID = {
      favoriteFood = "SODA_POP", dislikedFood = "MOOMOO_MILK", favoriteGame = "MATCH",
      hungerRate = 1.05, funRate = 1.10, sleepStart = 22, sleepWake = 9,
    },
    MAGBY = {
      favoriteFood = "RAGECANDYBAR", dislikedFood = "BERRY_JUICE", favoriteGame = "BOUNCE",
      hungerRate = 1.10, funRate = 1.00, sleepStart = 22, sleepWake = 8,
    },
    MIKON = {
      favoriteFood = "MOOMOO_MILK", dislikedFood = "FRESH_WATER", favoriteGame = "MATCH",
      hungerRate = 1.00, funRate = 1.00, sleepStart = 21, sleepWake = 9,
    },
    MONJA = {
      favoriteFood = "FRESH_WATER", dislikedFood = "SODA_POP", favoriteGame = "MEMORY",
      hungerRate = 0.95, funRate = 0.95, sleepStart = 20, sleepWake = 9,
    },
    GYOPIN = {
      favoriteFood = "FRESH_WATER", dislikedFood = "RAGECANDYBAR", favoriteGame = "BOUNCE",
      hungerRate = 1.00, funRate = 1.05, sleepStart = 21, sleepWake = 9,
    },
    PARA = {
      favoriteFood = "BERRY", dislikedFood = "SODA_POP", favoriteGame = "MEMORY",
      hungerRate = 0.95, funRate = 0.95, sleepStart = 20, sleepWake = 9,
    },
    HINAZU = {
      favoriteFood = "BERRY_JUICE", dislikedFood = "MOOMOO_MILK", favoriteGame = "BOUNCE",
      hungerRate = 1.05, funRate = 1.10, sleepStart = 22, sleepWake = 8,
    },
    KONYA = {
      favoriteFood = "MOOMOO_MILK", dislikedFood = "LEMONADE", favoriteGame = "MATCH",
      hungerRate = 1.00, funRate = 1.10, sleepStart = 22, sleepWake = 9,
    },
    PUCHIKON = {
      favoriteFood = "RAGECANDYBAR", dislikedFood = "FRESH_WATER", favoriteGame = "BOUNCE",
      hungerRate = 1.10, funRate = 1.05, sleepStart = 22, sleepWake = 8,
    },
    BETOBEBI = {
      favoriteFood = "SODA_POP", dislikedFood = "BERRY", favoriteGame = "MATCH",
      hungerRate = 0.95, funRate = 0.95, sleepStart = 21, sleepWake = 10,
    },
    PUDI = {
      favoriteFood = "MOOMOO_MILK", dislikedFood = "SODA_POP", favoriteGame = "BOUNCE",
      hungerRate = 1.10, funRate = 1.10, sleepStart = 22, sleepWake = 8,
    },
    BARIRINA = {
      favoriteFood = "LEMONADE", dislikedFood = "RAGECANDYBAR", favoriteGame = "MEMORY",
      hungerRate = 1.00, funRate = 0.95, sleepStart = 21, sleepWake = 9,
    },
    TSUINZU = {
      favoriteFood = "BERRY_JUICE", dislikedFood = "MOOMOO_MILK", favoriteGame = "MATCH",
      hungerRate = 1.00, funRate = 1.00, sleepStart = 21, sleepWake = 9,
    },
  }
  local CARE_ACTION_FRIENDSHIP = 1
  local PREFERENCE_FRIENDSHIP_BONUS = 1
  local SICKNESS_CURE_FRIENDSHIP = 2

  -- Sleep foundation. 9 PM -> 9 AM remains the baseline, but the personality
  -- table above supplies deliberately small species-specific routine changes.
  local DEFAULT_SLEEP_START_HOUR = 21
  local DEFAULT_SLEEP_END_HOUR = 9
  local SLEEP_SCHEDULE_OVERRIDES = {}
  for species, profile in pairs(PERSONALITY_PROFILES) do
    SLEEP_SCHEDULE_OVERRIDES[species] = { start = profile.sleepStart, wake = profile.sleepWake }
  end
  local GOOD_SLEEP_REWARD_SECONDS = 6 * 60 * 60
  local GOOD_SLEEP_FRIENDSHIP = 2

  -- Inspected directly from Crystal's extracted frontpic animation sheets.
  -- Four babies have an unambiguous closed-eye pose; the others use the
  -- calmest available vanilla frame rather than introducing custom art.
  local SLEEP_FRAME_BY_SPECIES = {
    PICHU = 3,      -- eyes closed
    CLEFFA = 2,     -- user-selected sleep pose
    IGGLYBUFF = 3,  -- eyes closed
    TOGEPI = 2,     -- user-selected sleep pose
    TYROGUE = 4,    -- eyes closed
    SMOOCHUM = 1,   -- eyes closed
    ELEKID = 0,     -- user-selected sleep pose
    MAGBY = 1,      -- user-selected sleep pose
  }

  -- CARE is the sixth bottom icon.  This first full pass wires the authored
  -- STATUS / NEW EGG / SWITCH MON / PAUSE CARE / CANCEL hierarchy and gives
  -- the Nursery three persistent slots.  The current authored BARIRIINA art
  -- is the only hatchable baby in this prototype build; more species can be
  -- added to this table without changing the slot/menu machinery.
  local CARE_ITEMS = { "STATUS", "NEW EGG", "SWITCH MON", "PAUSE CARE", "CANCEL" }
  local ZELDA_MENU_ITEMS = { "NURSERY", "DROP OFF", "WITHDRAW", "ADOPT", "ABOUT CARE", "CANCEL" }

  -- Zelda's transfer panel starts row text at x=27 inside a 160px-wide
  -- Game Boy screen. Keep dynamic labels comfortably inside the box even if
  -- another mod supplies a long nickname/species string.
  local function zeldaTransferLabel(text)
    text = tostring(text or "")
    local maxChars = 13
    if #text <= maxChars then return text end
    return string.sub(text, 1, maxChars - 1) .. "."
  end

  -- Nursery CALL contacts. Zelda is the only v1-era contact for now, but the
  -- data-driven list intentionally gives later visitor/baby-playdate updates a
  -- place to add trainers without rebuilding the CALL UI.
  local CALL_CONTACTS = {
    { id = "zelda", label = "ZELDA" },
  }
  local CARE_VISIBLE_ROWS = 4
  local SLOT_COUNT = 3
  local EGG_COOLDOWN_SECONDS = 24 * 60 * 60
  local EGG_HATCH_MINUTES = 10
  local NURSERY_SHINY_DENOMINATOR = 20 -- 1-in-20 Nursery-generated Eggs
  local EGG_WIGGLE_START_MINUTES = 7
  -- Crystal's real EggAnimation script is:
  --   setrepeat 2
  --     frame 1, 04 / frame 0, 04 / frame 2, 04 / frame 0, 04
  --   dorepeat 1
  -- The two non-base pictures below are extracted from this Crystal ROM's
  -- EggPic/EggFrames/EggBitmasks data, not redrawn from a reference sheet.
  -- At 7+ in-game minutes we replay that authentic eight-step wiggle as short
  -- bursts, increasing how often the burst occurs as the ten-minute mark nears.
  local EGG_VANILLA_FRAME_SECONDS = 4 / 60
  local EGG_WIGGLE_SEQUENCE = { 1, 0, 2, 0, 1, 0, 2, 0 }
  local EGG_WIGGLE_REST = { 2.40, 1.40, 0.70 }

  -- Player-owned eggs can be entrusted to the Nursery only when their hidden
  -- hatch species is one of Crystal's eight released Baby Pokemon.  The
  -- species remains hidden from the player; this table is purely an internal
  -- eligibility check.  Spaceworld babies join this list once their real
  -- species records exist in the mod.
  local OFFICIAL_BABY_POOL = {
    "PICHU", "CLEFFA", "IGGLYBUFF", "TOGEPI",
    "TYROGUE", "SMOOCHUM", "ELEKID", "MAGBY",
  }

  local OFFICIAL_BABY_SPECIES = {
    PICHU = true, CLEFFA = true, IGGLYBUFF = true, TOGEPI = true,
    TYROGUE = true, SMOOCHUM = true, ELEKID = true, MAGBY = true,
  }


  local NEO = {
    pool = {
    "MIKON", "MONJA", "GYOPIN", "PARA", "HINAZU", "KONYA",
    "PUCHIKON", "BETOBEBI", "PUDI", "BARIRINA", "TSUINZU",
    },
    species = {},
  }
  for _, id in ipairs(NEO.pool) do NEO.species[id] = true end

  function NEO.yesFirst(opts)
    -- Neo Nursery confirmations should always start on YES. Future confirmation
    -- boxes should pass their options through this helper.
    opts = opts or {}
    opts.defaultNo = false
    return opts
  end

  function NEO.isNurseryBabySpecies(id)
    return id ~= nil and (OFFICIAL_BABY_SPECIES[id] == true or NEO.species[id] == true)
  end

  function NEO.giveFirstFriendshipEverstone(game, s)
    if type(s) ~= "table" or s.friendshipEverstoneGiftClaimed == true then
      return false, "CLAIMED"
    end
    local save = game and game.save
    if not save then return false, "NO SAVE" end

    if Bag.add(save, "EVERSTONE", 1, game.data) then
      s.friendshipEverstoneGiftClaimed = true
      s.friendshipEverstoneGiftPending = false
      mod.save:set("babycare", s)
      if game.data then Sound.play(game.data, "Sfx_Item") end
      return true, "GIVEN"
    end

    -- Don't silently lose a one-time reward to a full ITEM pocket. Zelda will
    -- remember the gift and hand it over on a later CALL once room exists.
    s.friendshipEverstoneGiftPending = true
    mod.save:set("babycare", s)
    return false, "FULL"
  end

  -- User-authored keep/remove masks for the eight official babies' CRYSTAL
  -- Nursery presentation. These are silhouette data only, not distributed
  -- game sprite assets: 1 bits keep pixels from the player's imported Crystal
  -- art, 0 bits make them transparent. This avoids the Gen II shade-0
  -- ambiguity without shipping vanilla Pokemon sprite PNGs in the mod.
  NEO.officialCrystalMasks = {
    PICHU = {
      front1 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0700000000", "0FF0000000", "0FFC000000", "0FFF000000",
        "07FF800F80", "07FF803FC0", "03FF80FFC0", "03FFF9FFC0",
        "01FFFFFFC0", "01FFFFFFC0", "00FFFFFFC0", "003FFFFF80",
        "007FFFFF80", "007FFFFF00", "00FFFFFF00", "00FFFFF800",
        "00FFFFF800", "007FFFF800", "007FFFF000", "003FFFF000",
        "001FFFE000", "007FFFC000", "00FFFFE000", "00FFFFF1E0",
        "007FFFF7E0", "001FFFFFF0", "001FFFFDF0", "000FFFF1F0",
        "000FFFE1F0", "001FFFC1F0", "003FFFC1C0", "003F07E000",
        "001C03E000", "000001C000", "0000000000", "0000000000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "03F0000000", "0FFC003F00",
        "1FFE00FFC0", "1FFFF9FFE0", "0FFFFFFFE0", "03FFFFFFC0",
        "00FFFFFF80", "003FFFFF00", "007FFFFF00", "007FFFFE00",
        "00FFFFF800", "00FFFFF800", "00FFFFF800", "007FFFF000",
        "007FFFF000", "003FFFF00E", "001FFFE03E", "001FFFF1FE",
        "003FFFF7FE", "003FFFFFFC", "001FFFFDE0", "000FFFF180",
        "000FFFE000", "001FFFC000", "003FFFC000", "003F07E000",
        "001C03E000", "000001C000", "0000000000", "0000000000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "0FF800000000", "1FFF00001C00", "1FFF80003E00",
        "1FFF80007F00", "1FFF83F07F80", "0FFF9FFE7FC0", "0FFFFFFFFFE0",
        "07FFFFFFFFF0", "07FFFFFFFFF8", "03FFFFFFFFF8", "03FFFFFFFFF8",
        "01FFFFFFFFF0", "00EFFFFFFFE0", "001FFFFFFFC0", "001FFFFFFF80",
        "001FFFFFFE00", "001FFFFFFE00", "001FFFFFFC00", "000FFFFFFC00",
        "000FFFFFF800", "0007FFFFF800", "0003FFFFF000", "0001FFFFE000",
        "00007FFFC000", "00603FFFE000", "00F87FFFF800", "00FE7FFFFC00",
        "00FFFFFFFC00", "01FFFFFFF800", "01FFFFFFF000", "01FDFFFFC000",
        "03FCFFFFC000", "03F87FFF8000", "03F8FFFFE000", "03FBFFFFF800",
        "01F7FFFFFC00", "0073FFFFF800", "0000FFFFE000", "00000FFC0000",
      } },
    },
    CLEFFA = {
      front1 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000E00000", "0001F80000", "0003FE0000", "0007FF0000",
        "000FFFE000", "00FFFFFC00", "07FFFFFF80", "1FFFFFFFE0",
        "3FFFFFFFF8", "3FFFFFFFFC", "3FFFFFFFFC", "3FFFFFFFF8",
        "1FFFFFFFF8", "1FFFFFFFF0", "0FFFFFFFF0", "07FFFFFFE0",
        "07FFFFFFC0", "1FFFFFFF80", "3FFFFFFF80", "3FFFFFFF80",
        "1FFFFFFF80", "0FFFFFFFC0", "07FFFFFFE0", "07FFFFFFF0",
        "03FFFFFFF0", "03FFFFFFF0", "01FFFFFFF0", "01FFFFFFE0",
        "00FFFFFFE0", "00FFFFFF80", "007C01F800", "0030007000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000E00000", "0001FC0000",
        "0003FFE000", "1FFFFFFC00", "3FFFFFFFF8", "3FFFFFFFFC",
        "3FFFFFFFFC", "3FFFFFFFFC", "1FFFFFFFF8", "1FFFFFFFF8",
        "0FFFFFFFF0", "07FFFFFFF0", "07FFFFFFE0", "07FFFFFFE0",
        "07FFFFFFC0", "07FFFFFF80", "0FFFFFFF80", "0FFFFFFF80",
        "0FFFFFFF80", "0FFFFFFFC0", "07FFFFFFE0", "07FFFFFFF0",
        "03FFFFFFF0", "03FFFFFFF0", "01FFFFFFF0", "01FFFFFFE0",
        "00FFFFFFE0", "00FFFFFF80", "007C01F800", "0030007000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000003C00000", "00001FF00000", "00007FF80000", "0001FFFC0000",
        "0003FFFF0000", "000FFFFFC000", "007FFFFFF800", "01FFFFFFFF00",
        "07FFFFFFFFC0", "0FFFFFFFFFE0", "1FFFFFFFFFF0", "1FFFFFFFFFF0",
        "1FFFFFFFFFF0", "0FFFFFFFFFE0", "0FFFFFFFFFE0", "0FFFFFFFFFC0",
        "07FFFFFFFFC0", "07FFFFFFFF80", "03FFFFFFFF00", "03FFFFFFFF00",
        "03FFFFFFFE00", "03FFFFFFFE00", "03FFFFFFFE00", "03FFFFFFFF00",
        "03FFFFFFFF00", "01FFFFFFFF80", "03FFFFFFFF80", "03FFFFFFFF00",
        "07FFFFFFFE00", "07FFFFFFFC00", "07FFFFFFF800", "03FFFFFFF800",
        "03FFFFFFF000", "01FFFFFFF000", "01FFFFFFF800", "07FFFFFFFE00",
      } },
    },
    IGGLYBUFF = {
      front1 = { w = 40, h = 40, rows = {
        "00001C0000", "00007F0000", "0000FF8000", "0003FFE000",
        "000FFFF000", "001FFFF800", "001FFFF800", "001FFFF800",
        "000FFFF000", "000FFFF000", "001FFFF800", "003FFFFC00",
        "007FFFFE00", "00FFFFFF00", "01FFFFFF80", "01FFFFFF80",
        "03FFFFFFC0", "03FFFFFFC0", "03FFFFFFC0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "0FFFFFFFC0", "0FFFFFFFC0",
        "07FFFFFFC0", "01FFFFFF80", "01FFFFFF80", "00FFFFFF00",
        "007FFFFE00", "003FFFFF00", "001FFFFF80", "000FFFFF80",
        "000FFFC700", "001F7E0000", "001E000000", "000C000000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "00000E0000", "00003F8000", "00007FC000", "0001FFF000",
        "0007FFF800", "000FFFFC00", "000FFFFC00", "000FFFFC00",
        "000FFFFC00", "000FFFF800", "001FFFF800", "003FFFFC00",
        "007FFFFE00", "00FFFFFF00", "01FFFFFF80", "01FFFFFF80",
        "03FFFFFFC0", "03FFFFFFC0", "03FFFFFFC0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0",
        "1FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFC0", "1FFFFFFFE0",
        "03FFFFFFE0", "01FFFFFFC0", "01FFFFFF80", "00FFFFFF00",
        "007FFFFE00", "007FFFFC00", "00FFFFF800", "00FFFFF800",
        "00F9FFF800", "00607EF800", "0000007800", "0000003000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000078000000", "0001FE000000",
        "0003FF000000", "0007FF3C0000", "0007FFFE0000", "003FFFFF0000",
        "007FFFFF0000", "00FFFFFF8000", "00FFFFFF8000", "01FFFFFF8000",
        "01FFFFFF0000", "00FFFFFF0000", "00FFFFFE0000", "007FFFFE0000",
        "001FFFFF8000", "003FFFFFC000", "007FFFFFE000", "00FFFFFFF000",
        "01FFFFFFF800", "03FFFFFFFC00", "03FFFFFFFC00", "07FFFFFFFE00",
        "07FFFFFFFE00", "0FFFFFFFFF00", "0FFFFFFFFF00", "0FFFFFFFFF80",
        "1FFFFFFFFF80", "1FFFFFFFFFF8", "1FFFFFFFFFFC", "3FFFFFFFFFFC",
        "7FFFFFFFFFF8", "FFFFFFFFFFF0", "FFFFFFFFFFC0", "7FFFFFFFFF00",
        "07FFFFFFFE00", "07FFFFFFFE00", "03FFFFFFFC00", "03FFFFFFFC00",
        "01FFFFFFF800", "00FFFFFFF000", "007FFFFFE000", "003FFFFFC000",
        "000FFFFF8000", "0007FFFFC000", "0007FFFFC000", "0007FF8FC000",
      } },
    },
    TOGEPI = {
      front1 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000180000", "00003C0000", "0001FE3000", "0033FFFB00",
        "007FFFFF80", "007FFFFF80", "007FFFFF80", "003FFFFF00",
        "003FFFFF00", "001FFFFE00", "001FFFFF00", "003FFFFF00",
        "003FFFFF00", "003FFFFF80", "007FFFFF80", "007FFFFF80",
        "007FFFFF80", "007FFFFF00", "003FFFFF00", "001FFFFE00",
        "001FFFFE00", "000FFFFC00", "0007FFFC00", "0003FFF800",
        "0003FFE000", "0007FFF000", "000FF3F800", "0007E1F000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000180000", "00003C0000", "0001FE3000", "0033FFFB00",
        "007FFFFF80", "007FFFFF80", "007FFFFF80", "003FFFFF00",
        "003FFFFF00", "001FFFFE00", "001FFFFF00", "003FFFFF00",
        "003FFFFF00", "003FFFFF80", "007FFFFF80", "007FFFFF80",
        "007FFFFF80", "007FFFFF00", "003FFFFF00", "001FFFFE00",
        "001FFFFE00", "000FFFFC00", "0007FFFC00", "0003FFF800",
        "0003FFE000", "0007FFF000", "000FF3F800", "0007E1F000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000300600000", "0007C0FC0000", "0037F7FE1800", "007FFFFE7C00",
        "007FFFFFFC00", "007FFFFFFC00", "003FFFFFF800", "003FFFFFF800",
        "001FFFFFF000", "001FFFFFF000", "000FFFFFE000", "001FFFFFF000",
        "001FFFFFF800", "003FFFFFF800", "00FFFFFFFF00", "01FFFFFFFF80",
        "01FFFFFFFF80", "01FFFFFFFF00", "00FFFFFFFE00", "007FFFFFFC00",
        "007FFFFFFC00", "007FFFFFFC00", "003FFFFFF800", "003FFFFFF800",
        "001FFFFFF000", "001FFFFFF000", "000FFFFFE000", "0007FFFFC000",
        "000FFFFF8000", "003FFFFFF000", "007FFFFFFC00", "007FFFFFFE00",
        "003FFFFFFE00", "001FFFFFFC00", "0003FFFFF000", "00003FFF8000",
      } },
    },
    TYROGUE = {
      front1 = { w = 40, h = 40, rows = {
        "0000380000", "0000FC0000", "0001FCE000", "000DFDF000",
        "001EFFF000", "003FFFF000", "003FFFF000", "001FFFF800",
        "000FFFF800", "001FFFFC00", "001FFFFC00", "003FFFFE00",
        "003FFFFF06", "007FFFFF0F", "007FFFFF6F", "007FFFFEFF",
        "007FFFFCFF", "003FFFF8FF", "001FFFF07F", "000FFFE07F",
        "0007FFE07F", "001FFFF8FE", "00FFFFFFFC", "01FFFFFFF8",
        "07F87FFFF0", "0FF07FE7C0", "1FE07FF180", "3FF0FFF800",
        "3FF9FFFC00", "3FFBFFFC00", "7F33FFFC00", "7E03FFFE00",
        "3C01FCFF00", "1803F81F00", "0003E01F00", "000FC03FC0",
        "003FE03FE0", "007FE01FE0", "007FC00780", "003F000000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "0000380000", "0000FC0000", "0001FCE000", "000DFDF000",
        "001EFFF000", "003FFFF000", "003FFFF000", "001FFFF800",
        "000FFFF800", "001FFFFC00", "001FFFFC00", "003FFFFE00",
        "003FFFFF00", "007FFFFF00", "007FFFFF6C", "007FFFFEFE",
        "007FFFFCFE", "0F3FFFF8FE", "1F9FFFF07F", "3F8FFFE0FF",
        "3FC7FFE0FE", "3FC3FFF8FE", "1FC7FFFFFC", "1FEFFFFFF8",
        "0FFF7FFFF0", "07FE7FE7C0", "03FC7FF180", "00F0FFF800",
        "0001FFFC00", "0003FFFC00", "0003FFFC00", "0003FFFE00",
        "0001FCFF00", "0003F81F00", "0003E01F00", "000FC03FC0",
        "003FE03FE0", "007FE01FE0", "007FC00780", "003F000000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000038000000", "00007E000000", "00007F000000",
        "00007F000000", "0018FF000000", "007CFF060000", "00FCFF0F0000",
        "01FEFF1F8000", "01FFFF3FC000", "00FFFFFFC000", "00FFFFFF8000",
        "01FFFFFF0000", "03FFFFFF0000", "07FFFFFE0000", "07FFFFFE0000",
        "0FFFFFFF0000", "0FFFFFFF0000", "1FFFFFFF8000", "1FFFFFFF8060",
        "1FFFFFFF80F0", "1FFFFFFF81F0", "1FFFFFFF81E0", "1FFFFFFFC3F8",
        "0FFFFFFFC7FC", "0FFFFFFFC7FC", "07FFFFFF9FF8", "07FFFFFFFFE0",
        "03FFFFFFFFE0", "01FFFFFFFFE0", "007FFFFFFFF0", "001FFFFFFFF8",
        "0007FFFFF3F8", "000FFFFFF830", "001FFFFFF800", "003FFFE7F800",
        "003FFFEFFC00", "003FFFEFFF00", "007FFFEFFF80", "007FFFE7FF80",
        "007FFFF3FF00", "007FFFF1FE00", "00FFFFFBFE00", "00FFF9FFFC00",
        "00FFF8FFF800", "01FFF8FFF000", "01FFF87FE000", "01FFFC3FC000",
      } },
    },
    SMOOCHUM = {
      front1 = { w = 40, h = 40, rows = {
        "0002020000", "00078F0000", "007FDFE000", "00FFFFF000",
        "007FFFE000", "001FFF8000", "000FFF8000", "003FFFE000",
        "00FFFFF800", "01FFFFFC00", "03FFFFFE00", "07FFFFFF00",
        "0FFFFFFF80", "0FFFFFFF80", "1FFFFFFFC0", "1FFFFFFFC0",
        "1FFFFFFFC0", "3FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFE0",
        "3FFFFFFFE0", "1FFFFFFFE0", "1FFFFFFFC0", "0FFFFFFFC0",
        "0FFFFFFF80", "07FFFFFF00", "03FFFFFE00", "03FFFFF800",
        "03FFFFFC00", "03FFFFFE00", "01FFFFFF00", "00FFFFFF80",
        "007FFFFF80", "00FFFFF700", "00FFFFF000", "00FFFFF000",
        "00FFFFF000", "00FFFFE000", "00FFFFC000", "007E000000",
      } },
      front2 = { w = 40, h = 40, rows = {
        "0002020000", "00078F0000", "007FDFE000", "00FFFFF000",
        "007FFFE000", "001FFF8000", "000FFF8000", "003FFFE000",
        "00FFFFF800", "01FFFFFC00", "03FFFFFE00", "07FFFFFF00",
        "0FFFFFFF80", "0FFFFFFF80", "1FFFFFFFC0", "1FFFFFFFC0",
        "1FFFFFFFC0", "3FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFE0",
        "3FFFFFFFE0", "1FFFFFFFE0", "1FFFFFFFC0", "0FFFFFFFC0",
        "0FFFFFFF80", "07FFFFFF00", "03FFFFFE00", "03FFFFF800",
        "03FFFFFC00", "03FFFFFE00", "01FFFFFF00", "00FFFFFF80",
        "007FFFFF80", "00FFFFF700", "00FFFFF000", "00FFFFF000",
        "00FFFFF000", "00FFFFE000", "00FFFFC000", "007E000000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000000000000", "000000070000",
        "0000001FC000", "0007C07FE000", "001FF0FFE000", "003FFDFF0000",
        "007FFFFFF000", "00FFFFFFFC00", "01FFFFFFFE00", "01FFFFFFFE00",
        "00FFFFFFFC00", "0007FFFFE000", "001FFFFFF800", "003FFFFFFC00",
        "007FFFFFFE00", "00FFFFFFFF00", "00FFFFFFFF00", "01FFFFFFFF80",
        "01FFFFFFFF80", "03FFFFFFFF80", "03FFFFFFFFC0", "03FFFFFFFFC0",
        "03FFFFFFFFC0", "07FFFFFFFFE0", "07FFFFFFFFE0", "07FFFFFFFFE0",
        "07FFFFFFFFE0", "07FFFFFFFFE0", "07FFFFFFFFC0", "03FFFFFFFFC0",
        "03FFFFFFFF80", "01FFFFFFFF80", "01FFFFFFFF00", "00FFFFFFFE00",
        "007FFFFFFC00", "003FFFFFFE00", "000FFFFFFF00", "000FFFFFFF00",
        "003FFFFFFF00", "007FFFFFFE00", "00FFFFFFFC00", "00FFFFFFF000",
        "007FFFFFC000", "003FFFFFC000", "000FFFFFC000", "001FFFFFC000",
      } },
    },
    ELEKID = {
      front1 = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000007000000", "01C00F800000",
        "07F01FC07800", "0FF81FC0FC00", "1FF83DC1FE00", "1FFC3FC1FE00",
        "3FFC3FC3DE00", "3FFC3FC3FE00", "3FFC3FC3FC00", "7FFC1FC7FC00",
        "7FFC1FC7F800", "7FFC1FFFF800", "7FF81FFFF800", "7FF83FFFF800",
        "7FF87FFFF000", "3FF8FFFFF000", "3FF9FFFFF000", "1FF3FFFFF800",
        "0FF3FFFFF800", "0FF7FFFFF800", "07F7FFFFFC00", "03FFFFFFFC00",
        "01FFFFFFFC00", "007FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00",
        "000FFFFFFC00", "000FFFFFFF00", "000FFFFFFFC0", "0007FFFFFFE0",
        "0007FFFFF7E0", "0007FFFFF7F0", "0003FFFFEFF0", "0003FFFFEFF8",
        "0001FFFFCFF8", "0001FFFF8FFC", "0001FFFE0FFC", "0003FFFC0FFC",
        "000FE7FC0FFE", "003FF03E0FFE", "007FF07F9FFE", "007FF07FDFFE",
        "007FE07FEFFC", "003F003FE3FC", "0000001FE1F8", "00000007C0C0",
      } },
      front2 = { w = 48, h = 48, rows = {
        "01C000000000", "0FE007000000", "1FF00F800000", "3FF01FC07800",
        "3FF83FE0FC00", "7FF83FE1FE00", "7FFC7FE3FF00", "7FFC7FE3FF00",
        "7FFC7FE7FF00", "7FFC7FE7FF00", "7FFC7FE7FE00", "7FFC3FEFFE00",
        "7FFC3FEFFC00", "3FFC3FFFFC00", "3FF83FFFFC00", "1FF83FFFF800",
        "1FF87FFFF800", "0FF0FFFFF800", "0FF1FFFFF800", "07E3FFFFF800",
        "03E3FFFFF800", "01F7FFFFF800", "00FFFFFFFC00", "007FFFFFFC00",
        "001FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00",
        "000FFFFFFC00", "000FFFFFFF00", "000FFFFFFFC0", "0007FFFFFFE0",
        "0007FFFFF7E0", "0007FFFFF7F0", "0003FFFFEFF0", "0003FFFFEFF8",
        "0001FFFFCFF8", "0001FFFF8FFC", "0001FFFE0FFC", "0003FFFC0FFC",
        "000FE7FC1FFC", "003FF03E3FFC", "007FF07FBFFC", "007FF07FDFF8",
        "007FE07FEFF8", "003F003FEFF0", "0000001FE7C0", "00000007C000",
      } },
      back = { w = 48, h = 48, rows = {
        "000003800000", "000007C00000", "00E00FE00300", "01F00FE01F80",
        "03F81FE03FC0", "07F81EE03FE0", "07B81EE07FF0", "07B81FE0FFF8",
        "03FC1FE1FFF8", "03FF1FE1FFFC", "03FF9FE0FFFC", "03FFDFE0FFFC",
        "03FFFFE0FFFE", "07FFFFE0FFFE", "0FFFFFE0FFFF", "0FFFFFF0FFFF",
        "1FFFFFF8FFFF", "3FFFFFFCFFFF", "3FFFFFFE7FFF", "7FFFFFFF7FFF",
        "7FFFFFFFFFFF", "7FFFFFFFFFFF", "7FFFFFFFFFFF", "FFFFFFFFFFFE",
        "FFFFFFFFFFFE", "FFFFFFFFFFFE", "FFFFFFFFFFFC", "7FFFFFFFFFFC",
        "7FFFFFFFFFF8", "7FFFFFFFFFF8", "3FFFFFFFFFF0", "1FFFFFFFFFE0",
        "1FFFFFFFFF80", "1FFFFFFFF000", "1FFFFFFFF000", "0FFFFFFFF000",
        "0FFFFFFFF000", "0FFFFFFFE000", "07FFFFFFE000", "07FFFFFFC000",
        "03FFFFFFC000", "03FFFFFF8000", "01FFFFFF8000", "00FFFFFF0000",
        "007FFFFE0000", "003FFFFF0000", "000FFFFF0000", "0001FFBF8000",
      } },
    },
    MAGBY = {
      front1 = { w = 48, h = 48, rows = {
        "000000000000", "0000007C0000", "000000FEE000", "00000FFFF800",
        "00003FFFFC00", "00007FFFFE00", "00007FFFFF00", "0000FFFFFF00",
        "0000FFFFFF00", "0000FFFFFF00", "00007FFFFE00", "00003FFFFE00",
        "00001FFFFF00", "00000FFFFF80", "00003FFFFF80", "00007FFFFF80",
        "00007FFFFF80", "00003FFFFF00", "00003FFFFE00", "00001FFFF800",
        "00000FFFF000", "00000FFFFCC0", "000001FFFFE0", "000007FFFFE0",
        "00001FFFFFE0", "00067FFFFFF8", "000FFFFFFFFC", "007FFFFFFFF8",
        "00FFFFFFFFF0", "007FFFFFFFE0", "003FFFFFC7C0", "003F7FFF8000",
        "003E7FFFC000", "00187FFFC0C0", "00007FFFE3E0", "00003FFFFFE0",
        "00003FFFFFC0", "00001FFFFF80", "00001FFFFF00", "00000FFFFE00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
      front2 = { w = 48, h = 48, rows = {
        "000000000000", "00007C000000", "0000FEE00000", "000FFFF80000",
        "003FFFFC0000", "007FFFFE0000", "007FFFFF0000", "00FFFFFF0000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "003FFFFE0000",
        "001FFFFF0000", "000FFFFF8000", "003FFFFF8000", "007FFFFF8000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "0E1FFFF80000",
        "1F1FFFF00000", "0E0FFFF00000", "0003FFF80000", "0000FFFE0000",
        "0001FFFF0000", "0003FFFF8000", "0007FFFF8000", "0007FFFFC000",
        "000FFFFFC000", "000FFFFFC000", "000FFFFF8600", "0007FFFFCF00",
        "0007FFFFEF00", "0003FFFFFF00", "0001FFFFFF00", "00007FFFFF00",
        "00003FFFFF00", "00003FFFFE00", "00001FFFFE00", "00000FFFFC00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
      back = { w = 48, h = 48, rows = {
        "000000000000", "000000000000", "000000000000", "000000000000",
        "000000000000", "000000000000", "000000380000", "000000FE0000",
        "000001FF3800", "00003BFFFE00", "0000FFFFFF00", "0001FFFFFF80",
        "0003FFFFFFC0", "0003FFFFFFC0", "0007FFFFFFC0", "0007FFFFFFC0",
        "0007FFFFFFE0", "0003FFFFFFE0", "0007FFFFFFF0", "0007FFFFFFF0",
        "000FFFFFFFF0", "000FFFFFFFE0", "000FFFFFFFE0", "000FFFFFFFC0",
        "0007FFFFFF80", "0007FFFFFF00", "0003FFFFFF00", "0001FFFFFFC0",
        "00007FFFFFE0", "00003FFFFFE0", "00001FFFFFE0", "00001FFFFFC0",
        "00000FFFFFC0", "00000FFFFFC0", "00000FFFFF80", "00006FFFFF00",
        "0000FFFFF000", "0000FFFFE000", "0000FFFFE000", "3001FFFFE000",
        "7C01FFFFC000", "7F03FFFF8000", "3FE3FFFF0000", "3FFFFFFF0000",
        "1FFFFFFF8000", "0FFFFFFF8000", "07FFFFFF8000", "03FFFFFF8000",
      } },
    },
  }


  -- Neo Nursery's reconstructed/cut baby roster. The historical demo records
  -- mostly carried placeholder 50/50/50/50/50/50 stats, so these are authored
  -- baby-scale spreads agreed for Neo Nursery. PARA intentionally stays pure
  -- BUG and BARIRINA pure NORMAL; TSUINZU preserves the beta DARK/NORMAL idea.
  NEO.content = {
    MIKON = {
      name = "MIKON", dex = 252, evolvesInto = "VULPIX", evolutionLevel = 13,
      types = { "FIRE" },
      stats = { hp = 35, attack = 35, defense = 35, specialAttack = 45, specialDefense = 55, speed = 55 },
      eggMoves = { "HYPNOSIS", "FAINT_ATTACK" }, art = "mikon",
    },
    MONJA = {
      name = "MONJA", dex = 253, evolvesInto = "TANGELA", evolutionLevel = 22,
      types = { "GRASS" },
      stats = { hp = 45, attack = 40, defense = 75, specialAttack = 65, specialDefense = 40, speed = 35 },
      eggMoves = { "CONFUSION", "REFLECT" }, art = "monja",
    },
    GYOPIN = {
      name = "GYOPIN", dex = 254, evolvesInto = "GOLDEEN", evolutionLevel = 16,
      types = { "WATER" },
      stats = { hp = 35, attack = 50, defense = 45, specialAttack = 30, specialDefense = 40, speed = 50 },
      eggMoves = { "PSYBEAM", "HAZE" }, art = "gyopin",
    },
    PARA = {
      name = "PARA", dex = 255, evolvesInto = "PARAS", evolutionLevel = 12,
      types = { "BUG" },
      stats = { hp = 30, attack = 50, defense = 40, specialAttack = 35, specialDefense = 40, speed = 20 },
      eggMoves = { "PSYBEAM", "PURSUIT" }, art = "para",
    },
    HINAZU = {
      name = "HINAZU", dex = 256, evolvesInto = "DODUO", evolutionLevel = 16,
      types = { "NORMAL", "FLYING" },
      stats = { hp = 30, attack = 60, defense = 35, specialAttack = 30, specialDefense = 30, speed = 55 },
      eggMoves = { "QUICK_ATTACK", "FAINT_ATTACK" }, art = "hinazu",
    },
    KONYA = {
      name = "KONYA", dex = 257, evolvesInto = "MEOWTH", evolutionLevel = 14,
      types = { "NORMAL" },
      stats = { hp = 35, attack = 35, defense = 30, specialAttack = 35, specialDefense = 35, speed = 70 },
      eggMoves = { "CHARM", "HYPNOSIS" }, art = "konya",
    },
    PUCHIKON = {
      name = "PUCHIKON", dex = 258, evolvesInto = "PONYTA", evolutionLevel = 20,
      types = { "FIRE" },
      stats = { hp = 40, attack = 60, defense = 45, specialAttack = 50, specialDefense = 50, speed = 60 },
      eggMoves = { "DOUBLE_KICK", "FLAME_WHEEL" }, art = "puchikon",
    },
    BETOBEBI = {
      name = "BETOBEBI", dex = 259, evolvesInto = "GRIMER", evolutionLevel = 19,
      types = { "POISON" },
      stats = { hp = 60, attack = 55, defense = 40, specialAttack = 30, specialDefense = 40, speed = 20 },
      eggMoves = { "LICK", "MEAN_LOOK" }, art = "betobebi",
    },
    PUDI = {
      name = "PUDI", dex = 260, evolvesInto = "GROWLITHE", evolutionLevel = 13,
      types = { "FIRE" },
      stats = { hp = 40, attack = 50, defense = 35, specialAttack = 50, specialDefense = 40, speed = 45 },
      eggMoves = { "CRUNCH", "SAFEGUARD" }, art = "pudi",
    },
    BARIRINA = {
      name = "BARIRINA", dex = 261, evolvesInto = "MR__MIME", evolutionLevel = 15,
      types = { "NORMAL" },
      stats = { hp = 35, attack = 30, defense = 50, specialAttack = 65, specialDefense = 75, speed = 55 },
      eggMoves = { "FUTURE_SIGHT", "HYPNOSIS" }, art = "baririna",
    },
    TSUINZU = {
      name = "TSUINZU", dex = 262, evolvesInto = "GIRAFARIG", evolutionLevel = 29,
      types = { "DARK", "NORMAL" },
      stats = { hp = 45, attack = 45, defense = 45, specialAttack = 55, specialDefense = 45, speed = 55 },
      eggMoves = { "FUTURE_SIGHT", "FORESIGHT" }, art = "tsuinzu",
    },
  }

  -- Neo babies are Nursery-exclusive content. They remain fully registered so
  -- adopted babies behave like real Crystal species, but external generators
  -- should not pull them into random encounters, rentals, factory pools, or
  -- procedurally generated trainer parties.  Keep one authoritative mapping
  -- here so the guard can substitute the corresponding final-family species
  -- without requiring compatibility patches in every other mod.
  NEO.externalReplacement = {}
  for _, id in ipairs(NEO.pool) do
    local spec = NEO.content[id]
    NEO.externalReplacement[id] = spec and spec.evolvesInto or nil
  end

  function NEO.isExclusiveSpecies(id)
    return id ~= nil and NEO.species[id] == true
  end

  function NEO.externalSafeSpecies(id)
    if NEO.isExclusiveSpecies(id) then
      return NEO.externalReplacement[id] or id
    end
    return id
  end

  -- Public compatibility seam for future mods that want to filter candidate
  -- pools before presenting them. Existing mods do not need to call this for
  -- the common battle/encounter creation paths because the guards below also
  -- enforce the rule at runtime.
  mod.exports.isNeoNurseryExclusiveSpecies = NEO.isExclusiveSpecies
  mod.exports.externalSpeciesAllowed = function(id)
    return not NEO.isExclusiveSpecies(id)
  end

  -- Mon.new is the common Gen II builder used by rentals, generated parties,
  -- gifts and wild encounters.  Guard it once at the module level so a mod
  -- that blindly samples every registered species gets a safe family member
  -- instead of leaking a Neo baby. Neo Nursery explicitly opts in through the
  -- private `neoNurseryAllowExclusive` option when it creates its own babies.
  -- The shared sentinel makes hot reloads update the tables instead of stacking
  -- wrappers around Mon.new.
  do
    local guard = rawget(Mon, "_neoNurseryExclusiveGuard")
    if type(guard) ~= "table" or type(guard.originalNew) ~= "function" then
      guard = {
        originalNew = Mon.new,
        species = {},
        replacement = {},
      }
      rawset(Mon, "_neoNurseryExclusiveGuard", guard)
      Mon.new = function(data, species, level, opts)
        local active = rawget(Mon, "_neoNurseryExclusiveGuard")
        if active and active.species and active.species[species]
            and not (opts and opts.neoNurseryAllowExclusive == true) then
          species = (active.replacement and active.replacement[species]) or species
        end
        return active.originalNew(data, species, level, opts)
      end
    end
    guard.species = {}
    guard.replacement = {}
    for _, id in ipairs(NEO.pool) do
      guard.species[id] = true
      guard.replacement[id] = NEO.externalReplacement[id]
    end
  end

  -- Post-process the two engine-wide generation seams at a deliberately high
  -- priority. This catches randomizers that rewrite encounter results and mods
  -- that synthesize trainer parties after vanilla data has already been read.
  mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
    local rolled = nextFn(enc, ctx)
    if rolled and NEO.isExclusiveSpecies(rolled.species) then
      rolled.species = NEO.externalSafeSpecies(rolled.species)
    end
    return rolled
  end, 10000)

  local function rebuildExternalMon(mon)
    if type(mon) ~= "table" or not NEO.isExclusiveSpecies(mon.species) then
      return mon
    end
    local game = mod.game
    local data = game and game.data
    local species = NEO.externalSafeSpecies(mon.species)
    if not (data and data.pokemon and data.pokemon[species]) then
      mon.species = species
      mon.name = species
      return mon
    end
    local opts = {
      dvs = mon.dvs,
      statExp = mon.statExp,
      moves = mon.moves,
      item = mon.item,
      happiness = mon.happiness,
      hp = nil,
      shiny = mon.shiny,
      caughtLevel = mon.caughtLevel,
      caughtTime = mon.caughtTime,
      caughtLocation = mon.caughtLocation,
      caughtByGender = mon.caughtByGender,
    }
    local rebuilt = Mon.new(data, species, tonumber(mon.level) or 5, opts)
    if not rebuilt then return mon end
    rebuilt.nickname = mon.nickname
    rebuilt.ot = mon.ot
    rebuilt.otName = mon.otName
    rebuilt.otId = mon.otId
    rebuilt.status = mon.status
    if mon.hp ~= nil and mon.maxHp and mon.maxHp > 0 and rebuilt.maxHp then
      local ratio = math.max(0, math.min(1, mon.hp / mon.maxHp))
      rebuilt.hp = math.max(mon.hp > 0 and 1 or 0, math.floor(rebuilt.maxHp * ratio + 0.5))
    end
    return rebuilt
  end

  mod.hooks:wrap("trainer.party", function(nextFn, classId, memberId, party)
    local out = nextFn(classId, memberId, party) or party
    if type(out) ~= "table" then return out end
    for i, mon in ipairs(out) do
      out[i] = rebuildExternalMon(mon)
    end
    return out
  end, 10000)

  -- Unlocked Neo eggs are shown as distinct selectable eggs. These authored
  -- four-colour ramps are sampled from each supplied baby sprite so the EggPic
  -- reads like that species without shipping or altering Crystal's EggPic art.
  NEO.eggPalettes = {
    MIKON     = { {255,241,230}, {230,84,68},  {150,27,39},  {0,0,0} },
    MONJA     = { {242,236,255}, {109,89,199}, {125,36,36},  {0,0,0} },
    GYOPIN    = { {255,238,211}, {255,169,92}, {223,85,44},  {0,0,0} },
    PARA      = { {255,225,190}, {255,139,70}, {205,39,31},  {0,0,0} },
    HINAZU    = { {255,239,220}, {210,142,98}, {141,71,37},  {0,0,0} },
    KONYA     = { {255,246,192}, {247,212,93}, {151,54,18},  {0,0,0} },
    PUCHIKON  = { {255,231,173}, {252,128,3},  {240,30,0},   {0,0,0} },
    BETOBEBI  = { {255,216,244}, {236,16,163}, {98,8,98},    {0,0,0} },
    PUDI      = { {255,231,173}, {249,179,51}, {186,36,20},  {0,0,0} },
    BARIRINA  = { {255,226,255}, {250,137,250},{224,56,104}, {0,0,0} },
    TSUINZU   = { {242,222,255}, {180,84,255}, {111,45,206}, {0,0,0} },
  }

  -- Visible alpha bounds for the supplied 56x56 Nursery sprites. Thought
  -- bubbles use these rather than the full transparent canvas, keeping the
  -- bubble close to the baby's actual head/pose. Shiny sprites share the same
  -- silhouettes as their normal counterparts.
  NEO.spriteBounds = {
    PICHU = { front1 = { left = 15, top = 22, right = 44, bottom = 52 }, front2 = { left = 13, top = 23, right = 43, bottom = 51 }, back = { left = 11, top = 20, right = 52, bottom = 56 } },
    CLEFFA = { front1 = { left = 10, top = 18, right = 46, bottom = 56 }, front2 = { left = 11, top = 18, right = 46, bottom = 56 }, back = { left = 12, top = 10, right = 53, bottom = 56 } },
    IGGLYBUFF = { front1 = { left = 10, top = 22, right = 43, bottom = 54 }, front2 = { left = 12, top = 21, right = 44, bottom = 54 }, back = { left = 9, top = 21, right = 55, bottom = 56 } },
    TOGEPI = { front1 = { left = 17, top = 24, right = 42, bottom = 53 }, front2 = { left = 16, top = 23, right = 43, bottom = 54 }, back = { left = 15, top = 19, right = 49, bottom = 56 } },
    TYROGUE = { front1 = { left = 8, top = 16, right = 48, bottom = 56 }, front2 = { left = 8, top = 16, right = 47, bottom = 56 }, back = { left = 8, top = 18, right = 56, bottom = 56 } },
    SMOOCHUM = { front1 = { left = 9, top = 17, right = 47, bottom = 55 }, front2 = { left = 10, top = 17, right = 47, bottom = 55 }, back = { left = 12, top = 12, right = 52, bottom = 56 } },
    ELEKID = { front1 = { left = 15, top = 20, right = 38, bottom = 55 }, front2 = { left = 16, top = 22, right = 39, bottom = 54 }, back = { left = 15, top = 12, right = 48, bottom = 56 } },
    MAGBY = { front1 = { left = 12, top = 8, right = 53, bottom = 56 }, front2 = { left = 12, top = 8, right = 51, bottom = 56 }, back = { left = 10, top = 16, right = 52, bottom = 56 } },
    MIKON = { front1 = { left = 11, top = 19, right = 47, bottom = 54 }, front2 = { left = 11, top = 20, right = 43, bottom = 52 }, back = { left = 8, top = 10, right = 55, bottom = 56 } },
    MONJA = { front1 = { left = 8, top = 18, right = 48, bottom = 53 }, front2 = { left = 8, top = 21, right = 48, bottom = 55 }, back = { left = 8, top = 17, right = 56, bottom = 56 } },
    GYOPIN = { front1 = { left = 11, top = 20, right = 43, bottom = 54 }, front2 = { left = 10, top = 19, right = 44, bottom = 52 }, back = { left = 12, top = 28, right = 50, bottom = 56 } },
    PARA = { front1 = { left = 12, top = 17, right = 42, bottom = 55 }, front2 = { left = 8, top = 24, right = 46, bottom = 55 }, back = { left = 13, top = 15, right = 53, bottom = 56 } },
    HINAZU = { front1 = { left = 8, top = 16, right = 48, bottom = 56 }, front2 = { left = 8, top = 16, right = 46, bottom = 56 }, back = { left = 8, top = 14, right = 56, bottom = 56 } },
    KONYA = { front1 = { left = 8, top = 20, right = 48, bottom = 54 }, front2 = { left = 8, top = 23, right = 48, bottom = 53 }, back = { left = 11, top = 34, right = 55, bottom = 56 } },
    PUCHIKON = { front1 = { left = 9, top = 16, right = 47, bottom = 55 }, front2 = { left = 8, top = 18, right = 47, bottom = 56 }, back = { left = 9, top = 17, right = 55, bottom = 56 } },
    BETOBEBI = { front1 = { left = 11, top = 30, right = 45, bottom = 55 }, front2 = { left = 9, top = 31, right = 47, bottom = 53 }, back = { left = 8, top = 27, right = 55, bottom = 56 } },
    PUDI = { front1 = { left = 14, top = 21, right = 44, bottom = 54 }, front2 = { left = 10, top = 23, right = 46, bottom = 54 }, back = { left = 14, top = 16, right = 47, bottom = 56 } },
    BARIRINA = { front1 = { left = 9, top = 16, right = 46, bottom = 56 }, front2 = { left = 13, top = 19, right = 44, bottom = 56 }, back = { left = 9, top = 20, right = 54, bottom = 56 } },
    TSUINZU = { front1 = { left = 9, top = 11, right = 54, bottom = 50 }, front2 = { left = 10, top = 8, right = 51, bottom = 55 }, back = { left = 8, top = 9, right = 56, bottom = 56 } },
  }

  NEO.officialCrystalActionMasks = {
    PICHU = {
      [1] = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "03F0000000", "0FFC003F00",
        "1FFE00FFC0", "1FFFF9FFE0", "0FFFFFFFE0", "03FFFFFFC0",
        "00FFFFFF80", "003FFFFF00", "007FFFFF00", "007FFFFE00",
        "00FFFFF800", "00FFFFF800", "00FFFFF800", "007FFFF000",
        "007FFFF000", "003FFFF00E", "001FFFE03E", "001FFFF1FE",
        "003FFFF7FE", "003FFFFFFC", "001FFFFDE0", "000FFFF180",
        "000FFFE000", "001FFFC000", "003FFFC000", "003F07E000",
        "001C03E000", "000001C000", "0000000000", "0000000000",
      } },
      [3] = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0700000000", "0FF0000000", "0FFC000000", "0FFF000000",
        "07FF800F80", "07FF803FC0", "03FF80FFC0", "03FFF9FFC0",
        "01FFFFFFC0", "01FFFFFFC0", "00FFFFFFC0", "003FFFFF80",
        "007FFFFF80", "007FFFFF00", "00FFFFFF00", "00FFFFF800",
        "00FFFFF800", "007FFFF800", "007FFFF000", "003FFFF000",
        "001FFFE000", "007FFFC000", "00FFFFE000", "00FFFFF1E0",
        "007FFFF7E0", "001FFFFFF0", "001FFFFDF0", "000FFFF1F0",
        "000FFFE1F0", "001FFFC1F0", "003FFFC1C0", "003F07E000",
        "001C03E000", "000001C000", "0000000000", "0000000000",
      } },
    },
    CLEFFA = {
      [2] = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000E00000", "0001FC0000",
        "0003FFE000", "1FFFFFFC00", "3FFFFFFFF8", "3FFFFFFFFC",
        "3FFFFFFFFC", "3FFFFFFFFC", "1FFFFFFFF8", "1FFFFFFFF8",
        "0FFFFFFFF0", "07FFFFFFF0", "07FFFFFFE0", "07FFFFFFE0",
        "07FFFFFFC0", "07FFFFFF80", "0FFFFFFF80", "0FFFFFFF80",
        "0FFFFFFF80", "0FFFFFFFC0", "07FFFFFFE0", "07FFFFFFF0",
        "03FFFFFFF0", "03FFFFFFF0", "01FFFFFFF0", "01FFFFFFE0",
        "00FFFFFFE0", "00FFFFFF80", "007C01F800", "0030007000",
      } },
      [3] = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000E00000", "0000180000",
        "00021C0000", "00047E0000", "0004FF0000", "0004FF0000",
        "000EFFE000", "00FFFFFC00", "07FFFFFF80", "1FFFFFFFE0",
        "3FFFFFFFF8", "3FFFFFFFFC", "3FFFFFFFFC", "3FFFFFFFF8",
        "1FFFFFFFF8", "1FFFFFFFF0", "0FFFFFFFF0", "07FFFFFFE0",
        "07FFFFFFC0", "1FFFFFFF80", "3FFFFFFF80", "3FFFFFFF80",
        "1FFFFFFF80", "0FFFFFFFC0", "07FFFFFFE0", "07FFFFFFF0",
        "03FFFFFFF0", "03FFFFFFF0", "01FFFFFFF0", "01FFFFFFE0",
        "00FFFFFFE0", "00FFFFFF80", "007C01F800", "0030007000",
      } },
    },
    IGGLYBUFF = {
      [2] = { w = 40, h = 40, rows = {
        "00000E0000", "00003F8000", "00007FC000", "0001FFF000",
        "0007FFF800", "000FFFFC00", "000FFFFC00", "000FFFFC00",
        "000FFFFC00", "000FFFF800", "001FFFF800", "003FFFFC00",
        "007FFFFE00", "00FFFFFF00", "01FFFFFF80", "01FFFFFF80",
        "03FFFFFFC0", "03FFFFFFC0", "03FFFFFFC0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0",
        "1FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFC0", "1FFFFFFFE0",
        "03FFFFFFE0", "01FFFFFFC0", "01FFFFFF80", "00FFFFFF00",
        "007FFFFE00", "007FFFFC00", "00FFFFF800", "00FFFFF800",
        "00F9FFF800", "00607EF800", "0000007800", "0000003000",
      } },
      [3] = { w = 40, h = 40, rows = {
        "00001C0000", "00007F0000", "0000FF8000", "0003FFE000",
        "000FFFF000", "001FFFF800", "001FFFF800", "001FFFF800",
        "000FFFF000", "000FFFF000", "001FFFF800", "003FFFFC00",
        "007FFFFE00", "00FFFFFF00", "01FFFFFF80", "01FFFFFF80",
        "03FFFFFFC0", "03FFFFFFC0", "03FFFFFFC0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0", "07FFFFFFE0",
        "07FFFFFFE0", "07FFFFFFE0", "0FFFFFFFC0", "0FFFFFFFC0",
        "07FFFFFFC0", "01FFFFFF80", "01FFFFFF80", "00FFFFFF00",
        "007FFFFE00", "003FFFFF00", "001FFFFF80", "000FFFFF80",
        "000FFFC700", "001F7E0000", "001E000000", "000C000000",
      } },
    },
    TOGEPI = {
      [1] = { w = 40, h = 40, rows = {
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000000000", "0000000000",
        "0000000000", "0000000000", "0000180000", "00003C0000",
        "00007E0000", "0019FFE600", "003FFFFF00", "003FFFFF00",
        "003FFFFF00", "003FFFFF00", "001FFFFE00", "001FFFFE00",
        "001FFFFF00", "003FFFFF00", "007FFFFF80", "00FFFFFF80",
        "00FFFFFF80", "00FFFFFF80", "007FFFFF00", "007FFFFF00",
        "003FFFFF00", "001FFFFE00", "001FFFFE00", "000FFFFC00",
        "0007FFFC00", "0003FFF800", "0003FFE000", "0003FFE000",
        "0007E3F000", "0007E3F000", "0007C1F000", "0003C1E000",
      } },
    },
    TYROGUE = {
      [2] = { w = 40, h = 40, rows = {
        "0000380000", "0000FC0000", "0001FCE000", "000DFDF000",
        "001EFFF000", "003FFFF000", "003FFFF000", "001FFFF800",
        "000FFFF800", "001FFFFC00", "001FFFFC00", "003FFFFE00",
        "003FFFFF00", "007FFFFF00", "007FFFFF6C", "007FFFFEFE",
        "007FFFFCFE", "0F3FFFF8FE", "1F9FFFF07F", "3F8FFFE0FF",
        "3FC7FFE0FE", "3FC3FFF8FE", "1FC7FFFFFC", "1FEFFFFFF8",
        "0FFF7FFFF0", "07FE7FE7C0", "03FC7FF180", "00F0FFF800",
        "0001FFFC00", "0003FFFC00", "0003FFFC00", "0003FFFE00",
        "0001FCFF00", "0003F81F00", "0003E01F00", "000FC03FC0",
        "003FE03FE0", "007FE01FE0", "007FC00780", "003F000000",
      } },
      [3] = { w = 40, h = 40, rows = {
        "0000380000", "0000FC0000", "0001FCE000", "000DFDF000",
        "001EFFF000", "003FFFF000", "003FFFF000", "001FFFF800",
        "000FFFF800", "001FFFFC00", "001FFFFC00", "003FFFFE00",
        "003FFFFF00", "007FFFFF00", "007FFFFF6C", "007FFFFEFE",
        "007FFFFCFE", "0F3FFFF8FE", "1F9FFFF07F", "3F8FFFE0FF",
        "3FC7FFE0FE", "3FC3FFF8FE", "1FC7FFFFFC", "1FEFFFFFF8",
        "0FFF7FFFF0", "07FE7FE7C0", "03FC7FF180", "00F0FFF800",
        "0001FFFC00", "0003FFFC00", "0003FFFC00", "0003FFFE00",
        "0001FCFF00", "0003F81F00", "0003E01F00", "000FC03FC0",
        "003FE03FE0", "007FE01FE0", "007FC00780", "003F000000",
      } },
    },
    SMOOCHUM = {
      [2] = { w = 40, h = 40, rows = {
        "0002020000", "00078F0000", "007FDFE000", "00FFFFF000",
        "007FFFE000", "001FFF8000", "000FFF8000", "003FFFE000",
        "00FFFFF800", "01FFFFFC00", "03FFFFFE00", "07FFFFFF00",
        "0FFFFFFF80", "0FFFFFFF80", "1FFFFFFFC0", "1FFFFFFFC0",
        "1FFFFFFFC0", "3FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFE0",
        "3FFFFFFFE0", "1FFFFFFFE0", "1FFFFFFFC0", "0FFFFFFFC0",
        "0FFFFFFF80", "07FFFFFF00", "03FFFFFE00", "03FFFFF800",
        "03FFFFFC00", "03FFFFFE00", "01FFFFFF00", "00FFFFFF80",
        "007FFFFF80", "00FFFFF700", "00FFFFF000", "00FFFFF000",
        "00FFFFF000", "00FFFFE000", "00FFFFC000", "007E000000",
      } },
      [3] = { w = 40, h = 40, rows = {
        "0002020000", "00078F0000", "007FDFE000", "00FFFFF000",
        "007FFFE000", "001FFF8000", "000FFF8000", "003FFFE000",
        "00FFFFF800", "01FFFFFC00", "03FFFFFE00", "07FFFFFF00",
        "0FFFFFFF80", "0FFFFFFF80", "1FFFFFFFC0", "1FFFFFFFC0",
        "1FFFFFFFC0", "3FFFFFFFE0", "3FFFFFFFE0", "3FFFFFFFE0",
        "3FFFFFFFE0", "1FFFFFFFE0", "1FFFFFFFC0", "0FFFFFFFC0",
        "0FFFFFFF80", "07FFFFFF00", "03FFFFFE00", "03FFFFF800",
        "03FFFFFC00", "03FFFFFE00", "01FFFFFF00", "00FFFFFF80",
        "007FFFFF80", "00FFFFF700", "00FFFFF000", "00FFFFF000",
        "00FFFFF000", "00FFFFE000", "00FFFFC000", "007E000000",
      } },
    },
    ELEKID = {
      [2] = { w = 48, h = 48, rows = {
        "01C000000000", "0FE007000000", "1FF00F800000", "3FF01FC07800",
        "3FF83FE0FC00", "7FF83FE1FE00", "7FFC7FE3FF00", "7FFC7FE3FF00",
        "7FFC7FE7FF00", "7FFC7FE7FF00", "7FFC7FE7FE00", "7FFC3FEFFE00",
        "7FFC3FEFFC00", "3FFC3FFFFC00", "3FF83FFFFC00", "1FF83FFFF800",
        "1FF87FFFF800", "0FF0FFFFF800", "0FF1FFFFF800", "07E3FFFFF800",
        "03E3FFFFF800", "01F7FFFFF800", "00FFFFFFFC00", "007FFFFFFC00",
        "001FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00",
        "000FFFFFFC00", "000FFFFFFF00", "000FFFFFFFC0", "0007FFFFFFE0",
        "0007FFFFF7E0", "0007FFFFF7F0", "0003FFFFEFF0", "0003FFFFEFF8",
        "0001FFFFCFF8", "0001FFFF8FFC", "0001FFFE0FFC", "0003FFFC0FFC",
        "000FE7FC1FFC", "003FF03E3FFC", "007FF07FBFFC", "007FF07FDFF8",
        "007FE07FEFF8", "003F003FEFF0", "0000001FE7C0", "00000007C000",
      } },
      [3] = { w = 48, h = 48, rows = {
        "01C000000000", "0FE007000000", "1FF00F800000", "3FF01FC07800",
        "3FF83FE0FC00", "7FF83FE1FE00", "7FFC7FE3FF00", "7FFC7FE3FF00",
        "7FFC7FE7FF00", "7FFC7FE7FF00", "7FFC7FE7FE00", "7FFC3FEFFE00",
        "7FFC3FEFFC00", "3FFC3FFFFC00", "3FF83FFFFC00", "1FF83FFFF800",
        "1FF87FFFF800", "0FF0FFFFF800", "0FF1FFFFF800", "07E3FFFFF800",
        "03E3FFFFF800", "01F7FFFFF800", "00FFFFFFFC00", "007FFFFFFC00",
        "001FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00",
        "000FFFFFFC00", "000FFFFFFF00", "000FFFFFFFC0", "0007FFFFFFE0",
        "0007FFFFF7E0", "0007FFFFF7F0", "0003FFFFEFF0", "0003FFFFEFF8",
        "0001FFFFCFF8", "0001FFFF8FFC", "0001FFFE0FFC", "0003FFFC0FFC",
        "000FE7FC1FFC", "003FF03E3FFC", "007FF07FBFFC", "007FF07FDFF8",
        "007FE07FEFF8", "003F003FEFF0", "0000001FE7C0", "00000007C000",
      } },
      [4] = { w = 48, h = 48, rows = {
        "01C000000000", "0FE007000000", "1FF00F800000", "3FF01FC07800",
        "3FF83FE0FC00", "7FF83FE1FE00", "7FFC7FE3FF00", "7FFC7FE3FF00",
        "7FFC7FE7FF00", "7FFC7FE7FF00", "7FFC7FE7FE00", "7FFC3FEFFE00",
        "7FFC3FEFFC00", "3FFC3FFFFC00", "3FF83FFFFC00", "1FF83FFFF800",
        "1FF87FFFF800", "0FF0FFFFF800", "0FF1FFFFF800", "07E3FFFFF800",
        "03E3FFFFF800", "01F7FFFFF800", "00FFFFFFFC00", "007FFFFFFC00",
        "001FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00", "000FFFFFFC00",
        "000FFFFFFC00", "000FFFFFFF00", "000FFFFFFFC0", "0007FFFFFFE0",
        "0007FFFFF7E0", "0007FFFFF7F0", "0003FFFFEFF0", "0003FFFFEFF8",
        "0001FFFFCFF8", "0001FFFF8FFC", "0001FFFE0FFC", "0003FFFC0FFC",
        "000FE7FC1FFC", "003FF03E3FFC", "007FF07FBFFC", "007FF07FDFF8",
        "007FE07FEFF8", "003F003FEFF0", "0000001FE7C0", "00000007C000",
      } },
    },
    MAGBY = {
      [1] = { w = 48, h = 48, rows = {
        "000000000000", "0000007C0000", "000000FEE000", "00000FFFF800",
        "00003FFFFC00", "00007FFFFE00", "00007FFFFF00", "0000FFFFFF00",
        "0000FFFFFF00", "0000FFFFFF00", "00007FFFFE00", "00003FFFFE00",
        "00001FFFFF00", "00000FFFFF80", "00001FFFFF80", "00003FFFFF80",
        "00003FFFFF80", "00003FFFFF00", "00001FFFFE00", "00001FFFF800",
        "00000FFFF000", "000007FFFCC0", "000001FFFFE0", "000007FFFFE0",
        "00001FFFFFE0", "00067FFFFFF8", "000FFFFFFFFC", "007FFFFFFFF8",
        "00FFFFFFFFF0", "007FFFFFFFE0", "003FFFFFC7C0", "003FFFFF8000",
        "003EFFFFC000", "0018FFFFC0C0", "0000FFFFE3E0", "00007FFFFFE0",
        "00007FFFFFC0", "00003FFFFF80", "00001FFFFF00", "00000FFFFE00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
      [2] = { w = 48, h = 48, rows = {
        "000000000000", "00007C000000", "0000FEE00000", "000FFFF80000",
        "003FFFFC0000", "007FFFFE0000", "007FFFFF0000", "00FFFFFF0000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "003FFFFE0000",
        "001FFFFF0000", "000FFFFF8000", "003FFFFF8000", "007FFFFF8000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "0E1FFFF80000",
        "1F1FFFF00000", "0E0FFFF00000", "0003FFF80000", "0000FFFE0000",
        "0001FFFF0000", "0003FFFF8000", "0007FFFF8000", "0007FFFFC000",
        "000FFFFFC000", "000FFFFFC000", "000FFFFF8600", "0007FFFFCF00",
        "0007FFFFEF00", "0003FFFFFF00", "0001FFFFFF00", "00007FFFFF00",
        "00003FFFFF00", "00003FFFFE00", "00001FFFFE00", "00000FFFFC00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
      [3] = { w = 48, h = 48, rows = {
        "000000000000", "00007C000000", "0000FEE00000", "000FFFF80000",
        "003FFFFC0000", "007FFFFE0000", "007FFFFF0000", "00FFFFFF0000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "003FFFFE0000",
        "001FFFFF0000", "000FFFFF8000", "003FFFFF8000", "007FFFFF8000",
        "007FFFFF0000", "603FFFFF0000", "F03FFFFE0000", "FE1FFFF80000",
        "780FFFF00000", "000FFFF00000", "0001FFF80000", "0000FFFE0000",
        "0001FFFF0000", "0003FFFF8000", "0007FFFF8000", "0007FFFFC000",
        "000FFFFFC000", "000FFFFFC000", "000FFFFF8600", "0007FFFFCF00",
        "0007FFFFEF00", "0003FFFFFF00", "0001FFFFFF00", "00007FFFFF00",
        "00003FFFFF00", "00003FFFFE00", "00001FFFFE00", "00000FFFFC00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
      [4] = { w = 48, h = 48, rows = {
        "000000000000", "00007C000000", "0000FEE00000", "000FFFF80000",
        "003FFFFC0000", "007FFFFE0000", "007FFFFF0000", "00FFFFFF0000",
        "00FFFFFF0000", "00FFFFFF0000", "007FFFFE0000", "003FFFFE0000",
        "001FFFFF0000", "000FFFFF8000", "003FFFFF8000", "007FFFFF8000",
        "007FFFFF0000", "003FFFFF0000", "003FFFFE0000", "001FFFF80000",
        "000FFFF00000", "000FFFF00000", "0001FFF80000", "0000FFFE0000",
        "0001FFFF0000", "0003FFFF8000", "0007FFFF8000", "0007FFFFC000",
        "000FFFFFC000", "000FFFFFC000", "000FFFFF8600", "0007FFFFCF00",
        "0007FFFFEF00", "0003FFFFFF00", "0001FFFFFF00", "00007FFFFF00",
        "00003FFFFF00", "00003FFFFE00", "00001FFFFE00", "00000FFFFC00",
        "00003FFFF800", "0000FFFFF000", "0003FFFFF800", "0007FFDFF800",
        "0003FF9FF800", "00007E1FF800", "0000000C3000", "000000000000",
      } },
    },
  }

  -- Hand-picked from the official Crystal frontpic animation frames.
  -- Eating uses open-mouth / expressive poses where available; idle
  -- flourishes expose more personality-specific Crystal animation.
  NEO.officialEatFrames = {
    -- Best available "eating / mouth open / excited" pose in each official
    -- Crystal frontpic animation. Smoochum frame 2 is its clearly open-mouth
    -- sprite; Magby frame 1 avoids the flame-spit frames while eating.
    PICHU = 1,
    CLEFFA = 3,
    IGGLYBUFF = 2,
    TOGEPI = 1,
    TYROGUE = 3,
    SMOOCHUM = 2,
    ELEKID = 3,
    MAGBY = 1,
  }
  NEO.officialFlourishFrames = {
    PICHU = { 1, 3, 1 },
    CLEFFA = { 2, 3, 2 },
    IGGLYBUFF = { 2, 3, 2 },
    TOGEPI = { 1, 1, 1 },
    TYROGUE = { 2, 3, 2 },
    SMOOCHUM = { 2, 3, 2 },
    ELEKID = { 2, 4, 2, 4, 2 },
    MAGBY = { 1, 2, 3, 4, 3, 2, 1 },
  }

  function NEO.officialMaskBounds(mask)
    if not (mask and mask.rows) then return nil end
    local left, top, right, bottom
    for y = 0, (tonumber(mask.h) or 0) - 1 do
      for x = 0, (tonumber(mask.w) or 0) - 1 do
        if NEO.officialMaskKeeps(mask, x, y) then
          left = left and math.min(left, x) or x
          top = top and math.min(top, y) or y
          right = right and math.max(right, x + 1) or (x + 1)
          bottom = bottom and math.max(bottom, y + 1) or (y + 1)
        end
      end
    end
    if left == nil then return nil end
    return { left = left, top = top, right = right, bottom = bottom }
  end

  function NEO.copyList(list)
    local out = {}
    for i, value in ipairs(list or {}) do
      if type(value) == "table" then
        local row = {}
        for k, v in pairs(value) do row[k] = v end
        out[i] = row
      else
        out[i] = value
      end
    end
    return out
  end

  -- Give every Neo baby a real engine-wide cry by borrowing the final-family
  -- species' Crystal cry program and raising its frequency offset.  +64 keeps
  -- the familiar family voice while making it read as a smaller/younger mon,
  -- and stays within the public Gen II cry registry's 0..255 pitch field for
  -- every parent used here.  Because this is registered in audio.cries under
  -- the Neo species ID, every normal engine call site gets it automatically:
  -- battle send-out/faint, Summary/Box/Day Care, hatching, trading, Hall of
  -- Fame, and Neo Nursery's own PLAY victory cry.
  NEO.CRY_PITCH_LIFT = 64
  NEO.parentCryPitch = {
    VULPIX = 79,
    TANGELA = 0,
    GOLDEEN = 128,
    PARAS = 32,
    DODUO = 187,
    MEOWTH = 119,
    PONYTA = 0,
    GRIMER = 0,
    GROWLITHE = 32,
    MR__MIME = 8,
    GIRAFARIG = 65,
  }

  for _, id in ipairs(NEO.pool) do
    local spec = NEO.content[id]
    local basePitch = tonumber(NEO.parentCryPitch[spec.evolvesInto]) or 0
    local babyPitch = math.min(255, math.max(0, basePitch + NEO.CRY_PITCH_LIFT))
    mod.content.cries:register(id, {
      base = spec.evolvesInto,
      pitch = babyPitch,
    })
  end

  -- Register the eleven cut babies as real Gen II species. Most battle/breeding
  -- metadata inherits from the final evolution-family member so adopted babies
  -- participate in normal Crystal systems; Neo Nursery owns their types, stats,
  -- happiness evolution, egg/adoption moves, artwork, and derived baby cry.
  for _, id in ipairs(NEO.pool) do
    local spec = NEO.content[id]
    local parent = mod.content.pokemon:get(spec.evolvesInto)
    if parent then
      local record = {
        id = id,
        name = spec.name,
        dex = spec.dex,
        types = NEO.copyList(spec.types),
        baseStats = spec.stats,
        catchRate = tonumber(parent.catchRate) or 190,
        baseExp = tonumber(parent.baseExp) or 64,
        growthRate = parent.growthRate or "MEDIUM_FAST",
        levelMoves = NEO.copyList(parent.levelMoves),
        -- Neo Nursery babies are raised through care and adoption, so their
        -- family evolution is tied to the real Gen II happiness byte rather
        -- than an arbitrary level gate. 100 Nursery Friendship synchronizes
        -- to 255 happiness, comfortably above Crystal's 220 threshold.
        evolutions = { { method = "EVOLVE_HAPPINESS", into = spec.evolvesInto } },
        eggMoves = NEO.copyList(spec.eggMoves),
        eggSteps = tonumber(parent.eggSteps) or 20,
        spriteFront = mod.path .. "/assets/neo_" .. spec.art .. "_front1.png",
        spriteBack = mod.path .. "/assets/neo_" .. spec.art .. "_back.png",
        picSize = 7,
        source = "Neo Nursery",
        trueColor = true,
        -- Cross-mod contract: these reconstructed babies are real adoptable
        -- species, but generic random/rental/encounter pools should ignore them.
        neoNurseryExclusive = true,
        excludeFromGenericRandomSpecies = true,
      }
      if parent.tmhm then record.tmhm = NEO.copyList(parent.tmhm) end
      if parent.eggGroups then record.eggGroups = NEO.copyList(parent.eggGroups) end
      if parent.eggGroupsRaw ~= nil then record.eggGroupsRaw = parent.eggGroupsRaw end
      if parent.genderRatio ~= nil then record.genderRatio = parent.genderRatio end
      if parent.items then record.items = NEO.copyList(parent.items) end
      record.cry = id
      mod.content.pokemon:register(id, record)

      -- Reuse the final-family icon assignment in Crystal's party/box menus.
      local iconName = mod.content.icons:get(spec.evolvesInto)
      if iconName then mod.content.icons:register(id, iconName) end
    else
      mod.log:warn("Neo Nursery could not register " .. id .. ": missing " .. tostring(spec.evolvesInto))
    end
  end

  NEO.shinySprites = {}
  for _, id in ipairs(NEO.pool) do
    local spec = NEO.content[id]
    NEO.shinySprites[id] = {
      front = mod.path .. "/assets/neo_" .. spec.art .. "_shiny_front1.png",
      back = mod.path .. "/assets/neo_" .. spec.art .. "_shiny_back.png",
    }
  end

  -- Per-Pokemon Sprite Style follows an adopted/withdrawn baby out of the
  -- Nursery. Official babies tagged `neoNurserySpriteStyle = "nursery"` use
  -- Neo Nursery's alternate artwork in Summary, battle, Hall of Fame, etc.;
  -- `"crystal"` falls through to the player's imported Crystal sprite.
  -- Cut babies already use Neo artwork as their registered species sprites.
  mod.hooks:wrap("pokemon.sprite", function(nextFn, path, ctx)
    local species = ctx and ctx.species
    local mon = ctx and ctx.mon
    local stem = species and NEO.artStems[species] or nil
    local neoStyle = species and mon and (
      NEO.species[species] == true
      or (OFFICIAL_BABY_SPECIES[species] == true
        and mon.neoNurserySpriteStyle == "nursery")
    )

    if neoStyle and stem then
      if tostring(ctx.kind or ""):match("_anim$") then
        return nextFn(path, ctx)
      end

      local side = ctx.side == "back" and "back" or "front1"

      -- Individual color systems must see palette-ready grayscale art. MML's
      -- palette mutation takes precedence inside its renderer; PokeSurvive's
      -- randomized palette remains the baseline when there is no MML color
      -- mutation. Both survive CRYSTAL <-> NEO style changes.
      if NEO.hasExternalDynamicPalette(mon, species) then
        ctx.trueColor = false
        return nextFn(mod.path .. "/assets/neo_" .. stem .. "_rand_" .. side .. ".png", ctx)
      end

      if OFFICIAL_BABY_SPECIES[species] == true
          and mon.neoNurserySpriteStyle == "nursery" then
        local shinyPart = mon.shiny == true and "_shiny_" or "_"
        ctx.trueColor = true
        return nextFn(mod.path .. "/assets/neo_" .. stem .. shinyPart .. side .. ".png", ctx)
      end
    end

    local shiny = species and NEO.shinySprites[species]
    if shiny and mon and mon.shiny == true then
      ctx.trueColor = true
      return nextFn(ctx.side == "back" and shiny.back or shiny.front, ctx)
    end
    return nextFn(path, ctx)
  end, 900)

  -- Adoption bonus move pools. The seven Crystal Odd Egg species receive two
  -- curated event / baby-line-exclusive moves when adopted. Togepi (and any
  -- future baby without a complete special pair) falls back to two moves from
  -- its real Crystal egg-move list instead.
  local ADOPTION_SPECIAL_MOVES = {
    PICHU     = { "DIZZY_PUNCH", "SWEET_KISS" },
    CLEFFA    = { "DIZZY_PUNCH", "SWEET_KISS" },
    IGGLYBUFF = { "DIZZY_PUNCH", "SWEET_KISS" },
    TYROGUE   = { "DIZZY_PUNCH", "TACKLE" },
    SMOOCHUM  = { "DIZZY_PUNCH", "SWEET_KISS" },
    ELEKID    = { "DIZZY_PUNCH", "PURSUIT" },
    MAGBY     = { "DIZZY_PUNCH", "FAINT_ATTACK" },
    MIKON     = { "HYPNOSIS", "FAINT_ATTACK" },
    MONJA     = { "CONFUSION", "REFLECT" },
    GYOPIN    = { "PSYBEAM", "HAZE" },
    PARA      = { "PSYBEAM", "PURSUIT" },
    HINAZU    = { "QUICK_ATTACK", "FAINT_ATTACK" },
    KONYA     = { "CHARM", "HYPNOSIS" },
    PUCHIKON  = { "DOUBLE_KICK", "FLAME_WHEEL" },
    BETOBEBI  = { "LICK", "MEAN_LOOK" },
    PUDI      = { "CRUNCH", "SAFEGUARD" },
    BARIRINA  = { "FUTURE_SIGHT", "HYPNOSIS" },
    TSUINZU   = { "FUTURE_SIGHT", "FORESIGHT" },
  }

  local BABY_DEFS = {
    PICHU      = { species = "PICHU",      nickname = "PICHU",      baseWeightTenths = 44 },
    CLEFFA     = { species = "CLEFFA",     nickname = "CLEFFA",     baseWeightTenths = 66 },
    IGGLYBUFF  = { species = "IGGLYBUFF",  nickname = "IGGLYBUFF",  baseWeightTenths = 22 },
    TOGEPI     = { species = "TOGEPI",     nickname = "TOGEPI",     baseWeightTenths = 33 },
    TYROGUE    = { species = "TYROGUE",    nickname = "TYROGUE",    baseWeightTenths = 463 },
    SMOOCHUM   = { species = "SMOOCHUM",   nickname = "SMOOCHUM",   baseWeightTenths = 132 },
    ELEKID     = { species = "ELEKID",     nickname = "ELEKID",     baseWeightTenths = 518 },
    MAGBY      = { species = "MAGBY",      nickname = "MAGBY",      baseWeightTenths = 472 },
    MIKON      = { species = "MIKON",      nickname = "MIKON",      baseWeightTenths = 99 },
    MONJA      = { species = "MONJA",      nickname = "MONJA",      baseWeightTenths = 121 },
    GYOPIN     = { species = "GYOPIN",     nickname = "GYOPIN",     baseWeightTenths = 55 },
    PARA       = { species = "PARA",       nickname = "PARA",       baseWeightTenths = 71 },
    HINAZU     = { species = "HINAZU",     nickname = "HINAZU",     baseWeightTenths = 88 },
    KONYA      = { species = "KONYA",      nickname = "KONYA",      baseWeightTenths = 66 },
    PUCHIKON   = { species = "PUCHIKON",   nickname = "PUCHIKON",   baseWeightTenths = 198 },
    BETOBEBI   = { species = "BETOBEBI",   nickname = "BETOBEBI",   baseWeightTenths = 143 },
    PUDI       = { species = "PUDI",       nickname = "PUDI",       baseWeightTenths = 126 },
    BARIRINA   = { species = "BARIRINA",   nickname = "BARIRINA",   gender = "female", baseWeightTenths = 130 },
    TSUINZU    = { species = "TSUINZU",    nickname = "TSUINZU",    baseWeightTenths = 187 },
    -- Legacy prototype spelling; save migration rewrites it to BARIRINA.
    BARIRIINA  = { species = "BARIRINA",   nickname = "BARIRINA",   gender = "female", baseWeightTenths = 130 },
  }

  NEO.artStems = {
    PICHU = "pichu", CLEFFA = "cleffa", IGGLYBUFF = "igglybuff", TOGEPI = "togepi",
    TYROGUE = "tyrogue", SMOOCHUM = "smoochum", ELEKID = "elekid", MAGBY = "magby",
    MIKON = "mikon", MONJA = "monja", GYOPIN = "gyopin", PARA = "para",
    HINAZU = "hinazu", KONYA = "konya", PUCHIKON = "puchikon", BETOBEBI = "betobebi",
    PUDI = "pudi", BARIRINA = "baririna", TSUINZU = "tsuinzu",
  }

  -- PokeSurvive RAND TYPES compatibility. Nursery-generated babies do not pass
  -- through the normal encounter/trainer randomizer seams, so give them a
  -- stable per-species type roll from PokeSurvive's active run seed. The roll
  -- is stored on the actual Pokemon record; adoption therefore preserves the
  -- exact types instead of changing the instant the baby leaves the Nursery.
  NEO.psRandomTypePool = {
    "NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE",
    "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC_TYPE", "BUG",
    "ROCK", "GHOST", "DRAGON", "DARK", "STEEL",
  }

  NEO.psTypeColors = {
    NORMAL = {232,224,202}, FIRE = {255,116,72}, WATER = {86,158,255},
    ELECTRIC = {255,220,72}, GRASS = {102,194,92}, ICE = {132,218,238},
    FIGHTING = {204,82,72}, POISON = {184,92,204}, GROUND = {218,176,104},
    FLYING = {152,154,238}, PSYCHIC_TYPE = {246,104,154}, BUG = {164,188,58},
    ROCK = {188,164,94}, GHOST = {120,104,174}, DRAGON = {108,84,230},
    DARK = {106,92,88}, STEEL = {174,184,204},
  }

  function NEO.psBridge()
    local ok,found=pcall(function() return mod:find("pokemon_survival") end)
    if not (ok and found and found.exports) then return nil end
    local bridge=found.exports.neoNursery
    return type(bridge)=="table" and bridge or nil
  end

  function NEO.psPrepareSpecies(game,species)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.prepareSpecies)=="function" then
      local ok,value=pcall(bridge.prepareSpecies,game,species)
      return ok and value==true
    end
    return false
  end

  function NEO.psRefreshMon(game,mon,resetMoves)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.refreshMon)=="function" then
      local ok,value=pcall(bridge.refreshMon,game,mon,resetMoves==true)
      return ok and value==true
    end
    return false
  end

  function NEO.psModLoaded(game)
    if NEO.psBridge() then return true end
    local save = game and game.save
    local meta = save and save.meta
    local mods = meta and meta.mods
    if type(mods) == "table" then
      for _, info in pairs(mods) do
        if type(info) == "table" and info.id == "pokemon_survival" then return true end
      end
      -- modData is intentionally persistent across launcher profile changes,
      -- so a leftover pokemon_survival table is NOT proof that the mod is
      -- loaded in the current session. save.meta.mods is the authoritative
      -- current-session list whenever it is available.
      return false
    end
    -- Fallback only for unusually early load paths where save metadata has
    -- not been populated yet. These globals exist only in a live PokeSurvive
    -- session and cannot be resurrected by stale save data.
    return rawget(_G, "PokeSurvive") ~= nil or rawget(_G, "PokeSurviveGoldTime") ~= nil
  end

  function NEO.psRandomState(game)
    if not NEO.psModLoaded(game) then return nil end
    local save = game and game.save
    local md = save and save.modData
    local ps = md and md.pokemon_survival
    return type(ps) == "table" and ps or nil
  end

  function NEO.psRandomTypesEnabled(game)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.randomTypesEnabled)=="function" then
      local ok,value=pcall(bridge.randomTypesEnabled)
      if ok then return value==true end
    end
    local ps = NEO.psRandomState(game)
    return ps and ps.random_types_enabled == true or false
  end

  function NEO.stableSpeciesHash(text)
    local h = 5381
    text = tostring(text or "")
    for i = 1, #text do h = (h * 131 + text:byte(i)) % 2147483647 end
    return h
  end

  function NEO.nurseryRandomTypeSignature(game, species)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.signatureForSpecies)=="function" then
      local ok,value=pcall(bridge.signatureForSpecies,game,species)
      if ok and value then return tostring(value) end
    end
    local ps = NEO.psRandomState(game)
    if not (ps and ps.random_types_enabled == true) then return nil end
    return tostring(math.floor(tonumber(ps.random_seed) or 0)) .. "|" .. tostring(species or "")
  end

  function NEO.rollNurseryTypes(game, species, currentTypes)
    local signature = NEO.nurseryRandomTypeSignature(game, species)
    if not signature then return currentTypes, nil end
    local ps = NEO.psRandomState(game) or {}
    local seed = (math.floor(tonumber(ps.random_seed) or 0) + NEO.stableSpeciesHash(species)) % 2147483647
    local function pick(salt)
      local n = (seed * (1103515245 + salt * 97) + 12345 + salt * 7919) % 2147483647
      return NEO.psRandomTypePool[(n % #NEO.psRandomTypePool) + 1]
    end
    local originalCount = (type(currentTypes) == "table" and currentTypes[2] and currentTypes[2] ~= currentTypes[1]) and 2 or 1
    local first = pick(1)
    if originalCount == 1 then return { first }, signature end
    local second = pick(2)
    local salt = 3
    while second == first and salt < 20 do second = pick(salt); salt = salt + 1 end
    return { first, second }, signature
  end

  function NEO.psTypesForSpecies(game,species,currentTypes)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.typesForSpecies)=="function" then
      local ok,value=pcall(bridge.typesForSpecies,game,species)
      if ok and type(value)=="table" and #value>0 then
        local out={}
        for i,v in ipairs(value) do out[i]=v end
        return out,NEO.nurseryRandomTypeSignature(game,species)
      end
    end
    return NEO.rollNurseryTypes(game,species,currentTypes)
  end

  function NEO.psPaletteForTypes(game,species,types)
    local bridge=NEO.psBridge()
    if bridge and type(bridge.paletteForTypes)=="function" then
      local ok,value=pcall(bridge.paletteForTypes,game,species,types)
      if ok and type(value)=="table" and #value>=4 then return value end
    end
    return NEO.randomTypePalette(types,false)
  end

  function NEO.baseNurseryTypes(game, species)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[species]
    local src = def and def.types
    if type(src) ~= "table" then return nil end
    local out = {}
    if src[1] ~= nil then out[1] = src[1] end
    if src[2] ~= nil and src[2] ~= src[1] then out[2] = src[2] end
    return #out > 0 and out or nil
  end

  function NEO.restoreInactiveNurseryTypes(game, mon)
    if type(mon) ~= "table" then return mon end
    if not mon.neoNurseryRandomTypesSignature
      and type(mon._pokesurviveNurseryTypes)~="table" then return mon end
    local base = NEO.baseNurseryTypes(game, mon.species)
    if base then
      mon.types={}
      for i,v in ipairs(base) do mon.types[i]=v end
    end
    mon.neoNurseryRandomTypesSignature = nil
    mon._pokesurviveNurserySignature = nil
    mon._pokesurviveNurseryTypes = nil
    return mon
  end

  function NEO.ensureNurseryRandomTypes(game, mon)
    if type(mon) ~= "table" or not mon.species then return mon end
    if not NEO.psRandomTypesEnabled(game) then
      -- Persistent PokeSurvive modData is not enough: if RAND TYPES is not
      -- actually active, clear every Nursery-specific random-type marker.
      return NEO.restoreInactiveNurseryTypes(game, mon)
    end

    local signature = NEO.nurseryRandomTypeSignature(game, mon.species)
    if signature
      and mon._pokesurviveNurserySignature == signature
      and type(mon._pokesurviveNurseryTypes)=="table"
      and #mon._pokesurviveNurseryTypes>0 then
      mon.types={}
      for i,v in ipairs(mon._pokesurviveNurseryTypes) do mon.types[i]=v end
      mon.neoNurseryRandomTypesSignature=signature
      return mon
    end

    local base = NEO.baseNurseryTypes(game, mon.species) or mon.types
    if type(base) ~= "table" then base = { "NORMAL" } end

    -- PokeSurvive 2.1.3+ supplies the authoritative family roll. Older builds
    -- fall back to Neo Nursery's legacy deterministic roller.
    local types, sig = NEO.psTypesForSpecies(game, mon.species, base)
    sig = sig or signature
    if type(types)=="table" and #types>0 then
      mon.types={}
      mon._pokesurviveNurseryTypes={}
      for i,v in ipairs(types) do
        mon.types[i]=v
        mon._pokesurviveNurseryTypes[i]=v
      end
      mon._pokesurviveNurserySignature=sig
      mon.neoNurseryRandomTypesSignature=sig
    end
    return mon
  end

  function NEO.blendColor(a, b, amount)
    if not b then return { a[1], a[2], a[3] } end
    amount = amount or 0.4
    return {
      math.floor(a[1] * (1 - amount) + b[1] * amount + 0.5),
      math.floor(a[2] * (1 - amount) + b[2] * amount + 0.5),
      math.floor(a[3] * (1 - amount) + b[3] * amount + 0.5),
    }
  end

  function NEO.scaledColor(c, factor)
    return {
      math.max(0, math.min(255, math.floor(c[1] * factor + 0.5))),
      math.max(0, math.min(255, math.floor(c[2] * factor + 0.5))),
      math.max(0, math.min(255, math.floor(c[3] * factor + 0.5))),
    }
  end

  function NEO.cinnabarPalette(data, mon)
    local f = type(mon) == "table" and mon.cinnabarFusion or nil
    if type(f) ~= "table" then return nil end

    -- MML's explicit four-colour override is already the final palette.
    if type(f.paletteOverride) == "table" then
      return f.paletteOverride
    end

    -- A donor-palette splice means "use this species' normal Crystal palette",
    -- matching Mutant Monster Lab's own effectivePalette() behavior.
    if f.paletteSpecies and data and data.gen2Palettes then
      return Palettes.monColors(data.gen2Palettes, f.paletteSpecies, false)
    end
    return nil
  end

  function NEO.hasExternalDynamicPalette(mon, species)
    local f = type(mon) == "table" and mon.cinnabarFusion or nil
    if type(f) == "table" and (f.paletteOverride or f.paletteSpecies) then
      return true
    end

    -- PokeSurvive RAND TYPES changes the registered cut-baby species itself.
    -- After adoption / stat refresh, the individual Nursery marker is not the
    -- only reliable proof that a reconstructed species needs palette-ready art.
    -- If RAND TYPES is live, every non-shiny Neo-exclusive cut baby should use
    -- the grayscale `_rand_` sprite so Summary, battle, Box, Hall of Fame, Dex,
    -- etc. can apply the species' seeded PokeSurvive palette.
    if type(mon) == "table" and mon.shiny == true then return false end
    if species and NEO.species[species] == true
        and NEO.psRandomTypesEnabled(nil) then
      return true
    end

    -- Official Nursery-raised babies still use their per-Pokemon marker because
    -- those are ordinary Crystal species and should not globally switch artwork.
    return type(mon) == "table" and (
      mon.neoNurseryRandomTypesSignature ~= nil
      or type(mon._pokesurviveNurseryTypes)=="table"
    )
  end

  function NEO.randomTypePalette(types, shiny)
    local t1 = type(types) == "table" and types[1] or "NORMAL"
    local t2 = type(types) == "table" and types[2] or nil
    local primary = NEO.psTypeColors[t1] or NEO.psTypeColors.NORMAL
    local secondary = t2 and NEO.psTypeColors[t2] or primary

    -- Keep dual-type palettes separated instead of averaging both hues into
    -- one muddy colour. The grayscale Nursery art maps its light/mid/dark
    -- ramps to these three entries, so this preserves a bright recognizable
    -- silhouette while still showing both randomized types. FIRE/GROUND, for
    -- example, becomes pale peach + warm sand + burnt orange rather than an
    -- all-over brown wash.
    local lightMix = shiny and 0.86 or 0.78
    local midMix = shiny and 0.34 or 0.18
    local darkScale = shiny and 0.84 or 0.72
    return {
      NEO.blendColor(primary, {255,255,255}, lightMix),
      NEO.blendColor(secondary, {255,255,255}, midMix),
      NEO.scaledColor(primary, darkScale),
      {0,0,0},
    }
  end

  local FOOD_WEIGHT_TENTHS = {
    BERRY = 1,
    BERRY_JUICE = 1,
    FRESH_WATER = 0,
    SODA_POP = 1,
    LEMONADE = 1,
    MOOMOO_MILK = 2,
    RAGECANDYBAR = 2,
  }

  -- Friendship is now paced around deliberate care rather than passive full
  -- meters. Every two AWAKE real hours we evaluate the current care state:
  -- excellent care earns a small +1, merely-okay care is neutral, and neglect
  -- costs Friendship. Sleeping time never advances this passive check.
  local HAPPINESS_STEP_SECONDS = 2 * 60 * 60

  local function clampMeter(v)
    v = tonumber(v) or 0
    -- Babycare meters use half-heart granularity.
    v = math.floor(v * 2 + 0.0001) / 2
    if v < 0 then return 0 end
    if v > 4 then return 4 end
    return v
  end

  -- Care needs use host / real-world elapsed time, deliberately independent
  -- from Crystal's RTC.  Awake care is intentionally Tamagotchi-like: Hunger
  -- loses half a heart every 45 minutes and Fun every 75 minutes before each
  -- species' mild personality modifier. Proper lights-off sleep slows both to
  -- one-sixth speed so an overnight sleep never asks the player to wake up and
  -- babysit meters. Clean remains entirely waste-driven.
  local CARE_HALF_HEART_SECONDS = {
    hunger = 45 * 60,
    fun = 75 * 60,
    clean = 6 * 60 * 60,
  }
  local SLEEP_CARE_DRAIN_FACTOR = 1 / 6

  local function wallNow()
    local ok, value = pcall(os.time)
    if ok and type(value) == "number" then return math.floor(value) end
    return 0
  end

  local function gameMinuteStamp(game)
    local save = game and game.save or nil
    local psClock = rawget(_G, "PokeSurviveGoldTime")
    if type(save) == "table" and type(psClock) == "table" and psClock.patched == true
        and tonumber(save._pokesurviveClockMinutes) ~= nil then
      local day = math.floor(tonumber(save._pokesurviveClockDay) or 0)
      local minute = math.floor(tonumber(save._pokesurviveClockMinutes) or 0)
      return day * 24 * 60 + minute
    end
    -- Vanilla Crystal's RTC runs 1:1 with host time.  This absolute-minute
    -- fallback gives eggs an unwrapped ten-minute timer without depending on
    -- a particular weekday field.  PokeSurvive automatically takes the arm
    -- above, so its explicit time jumps count for hatching but not care decay.
    return math.floor(wallNow() / 60)
  end

  local function sleepSchedule(species)
    local override = SLEEP_SCHEDULE_OVERRIDES[species or ""]
    return (override and override.start) or DEFAULT_SLEEP_START_HOUR,
      (override and override.wake) or DEFAULT_SLEEP_END_HOUR
  end

  local function currentGameMinuteOfDay(game)
    local save = game and game.save
    -- Always ask Gen1Recomp's public Crystal clock for the time the player is
    -- actually seeing. PokeSurvive patches Clock.minutes() while its synthetic
    -- clock is active; when that option is disabled, Clock.minutes() correctly
    -- falls back to Crystal's normal RTC. Reading PokeSurvive's saved minute
    -- field directly could leave Neo Nursery stuck on a stale old hour.
    return Clock.minutes(save)
  end

  local function currentGameHour(game)
    return currentGameMinuteOfDay(game) / 60
  end

  local function hourInWindow(hour, startHour, wakeHour)
    hour = math.floor(tonumber(hour) or 0) % 24
    startHour = math.floor(tonumber(startHour) or 21) % 24
    wakeHour = math.floor(tonumber(wakeHour) or 9) % 24
    if startHour == wakeHour then return true end
    if startHour < wakeHour then return hour >= startHour and hour < wakeHour end
    return hour >= startHour or hour < wakeHour
  end

  local function activeBabyRecord(s)
    return type(s) == "table" and s.slots and s.slots[s.activeSlot or 1] or nil
  end

  local function sleepWindowActiveFor(s, game)
    local slot = activeBabyRecord(s)
    if not (slot and slot.kind == "baby") then return false end
    local startHour, wakeHour = sleepSchedule(slot.species)
    return hourInWindow(currentGameHour(game), startHour, wakeHour)
  end

  -- Split a real-time care interval into chronological RTC sleep-window and
  -- awake segments. The game clock advances 1:1 with host time during normal
  -- play, so reconstructing backwards from the current RTC phase lets an
  -- overnight close/reopen correctly receive slow sleep drain instead of
  -- treating the whole absence as awake time. LIGHTS must actually be off for
  -- a sleep-window segment to count as sleeping.
  local function careTimelineSegments(s, game, lastAt, nowAt)
    local segments = {}
    local elapsed = math.max(0, (tonumber(nowAt) or 0) - (tonumber(lastAt) or 0))
    if elapsed <= 0 then return segments end

    local slot = activeBabyRecord(s)
    if not (slot and slot.kind == "baby") then
      segments[1] = { startAt = lastAt, endAt = nowAt, seconds = elapsed, inSleepWindow = false, sleeping = false, properSleep = false }
      return segments
    end

    local daySeconds = 24 * 60 * 60
    local startHour, wakeHour = sleepSchedule(slot.species)
    local sleepStart = (math.floor(startHour) % 24) * 60 * 60
    local sleepWake = (math.floor(wakeHour) % 24) * 60 * 60
    local currentPhase = ((currentGameMinuteOfDay(game) * 60) + ((tonumber(nowAt) or 0) % 60)) % daySeconds
    local phase = (currentPhase - (elapsed % daySeconds)) % daySeconds
    local cursor = tonumber(lastAt) or 0
    local remaining = elapsed
    local lightsOff = s.lightsOn == false
    local guard = 0

    local function phaseInSleepWindow(p)
      if sleepStart == sleepWake then return true end
      if sleepStart < sleepWake then return p >= sleepStart and p < sleepWake end
      return p >= sleepStart or p < sleepWake
    end

    while remaining > 0 and guard < 4096 do
      guard = guard + 1
      local inWindow = phaseInSleepWindow(phase)
      local toStart = (sleepStart - phase) % daySeconds
      local toWake = (sleepWake - phase) % daySeconds
      if toStart <= 0 then toStart = daySeconds end
      if toWake <= 0 then toWake = daySeconds end
      local toBoundary = math.min(toStart, toWake)
      if sleepStart == sleepWake then toBoundary = remaining end
      local dt = math.min(remaining, toBoundary)
      if dt <= 0 then dt = math.min(remaining, 1) end
      local segEnd = cursor + dt
      segments[#segments + 1] = {
        startAt = cursor, endAt = segEnd, seconds = dt,
        inSleepWindow = inWindow, sleeping = inWindow, properSleep = inWindow and lightsOff,
      }
      cursor = segEnd
      remaining = remaining - dt
      phase = (phase + dt) % daySeconds
    end

    if remaining > 0 then
      local inWindow = phaseInSleepWindow(phase)
      segments[#segments + 1] = {
        startAt = cursor, endAt = nowAt, seconds = remaining,
        inSleepWindow = inWindow, sleeping = inWindow, properSleep = inWindow and lightsOff,
      }
    end
    return segments
  end

  local function cloneBabyDef(id)
    local def = BABY_DEFS[id] or BABY_DEFS.BARIRINA
    return {
      kind = "baby",
      species = def.species,
      nickname = def.nickname,
      gender = def.gender,
      ageDays = 4,
      weightTenths = def.baseWeightTenths,
      happiness = 50,
      happinessRemainder = 0,
      hunger = 4,
      fun = 4,
      clean = 4,
      careLastRealAt = wallNow(),
      careRemainder = { hunger = 0, fun = 0, clean = 0 },
      digestion = 0,
      poopDueAt = nil,
      poopPendingWake = false,
      wastePresent = false,
      wasteCount = 0,
      wasteExposure = 0,
      wastePenalty = 0,
      devPoopQueued = false,
      dietStrain = 0,
      sicknessRisk = { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 },
      sickness = nil,
      sleepWalkIndex = nil,
      preferencesDiscovered = { favoriteFood = false, dislikedFood = false, favoriteGame = false },
    }
  end

  function NEO.randomIndex(n)
    if n <= 1 then return 1 end
    if love.math and love.math.random then return love.math.random(n) end
    return math.random(n)
  end

  local function randomOfficialBaby()
    return OFFICIAL_BABY_POOL[NEO.randomIndex(#OFFICIAL_BABY_POOL)]
  end

  function NEO.randomAvailable(_s)
    -- ODD EGG deliberately remains the canonical eight-baby pool. Neo babies
    -- are persistent, separately selectable coloured eggs once discovered.
    return randomOfficialBaby()
  end

  function NEO.shinyDVs()
    local attacks = { 2, 3, 6, 7, 10, 11, 14, 15 }
    return { attack = attacks[NEO.randomIndex(#attacks)], defense = 10, speed = 10, special = 10 }
  end

  function NEO.nonShinyDVs()
    local dvs
    repeat dvs = Mon.randomDVs() until not Mon.vanillaShiny(dvs)
    return dvs
  end

  function NEO.rollEggDVs()
    if NEO.randomIndex(NURSERY_SHINY_DENOMINATOR) == 1 then
      return NEO.shinyDVs(), true
    end
    return NEO.nonShinyDVs(), false
  end

  local function newNurseryMon(game, species, egg)
    -- PokeSurvive 2.1.4+ applies RAND TYPES/STATS/MOVES to Neo-exclusive
    -- species here before Mon.new reads their species definition.
    NEO.psPrepareSpecies(game, species)

    local data = game and game.data
    local level = (egg and egg.level) or Breeding.EGG_LEVEL or 5
    local opts = { happiness = Breeding.HATCH_HAPPINESS or 120, neoNurseryAllowExclusive = true }
    if egg then opts.dvs = egg.dvs; opts.moves = egg.moves; opts.shiny = egg.shiny == true end
    local mon = Mon.new(data, species, level, opts)
    if not mon then return nil end
    mon.neoNurseryRaised = true
    mon.neoNurseryFriendship = 0
    mon.neoNurseryWeightTenths = NEO.baseWeightTenths(species)
    mon.neoNurserySpriteStyle = OFFICIAL_BABY_SPECIES[species] and "crystal" or "nursery"
    NEO.ensureNurseryRandomTypes(game, mon)
    NEO.psRefreshMon(game, mon, egg == nil)
    NEO.ensureNurseryRandomTypes(game, mon)
    if egg and egg.experience ~= nil then mon.experience = egg.experience end
    mon.hp = mon.maxHp
    local player = game and game.save and game.save.player
    if player then
      mon.ot = player.name or mon.ot
      mon.otName = player.name or mon.otName
      mon.otId = player.id or mon.otId
    end
    return mon
  end

  local function nurseryBabyFromMon(mon, origin)
    if not mon then return nil end
    local def = BABY_DEFS[mon.species] or { species = mon.species, nickname = mon.name or mon.species, baseWeightTenths = 0 }
    local returning = origin == "player" and (
      mon.neoNurseryRaised == true
      or mon.neoNurseryFriendship ~= nil
      or mon.babycareAdoptionMoves ~= nil
      or mon.babycareAdoptionMoveSource ~= nil
    )
    local storedWeight = returning and tonumber(mon.neoNurseryWeightTenths) or nil
    local baby = {
      kind = "baby", origin = origin or "nursery", playerOwned = origin == "player",
      species = mon.species, nickname = mon.nickname or def.nickname or mon.name or mon.species,
      gender = mon.gender, ageDays = 0, birthRealAt = wallNow(),
      weightTenths = math.max(1, math.floor(storedWeight or def.baseWeightTenths or 1)),
      -- Newly hatched / newly deposited babies begin needing a little attention:
      -- 2 FOOD hearts, 2 FUN hearts, 4 CLEAN hearts.
      happiness = returning and NEO.nurseryFriendshipFromMon(mon) or 0,
      happinessRemainder = 0, hunger = 2, fun = 2, clean = 4,
      careLastRealAt = wallNow(),
      careRemainder = { hunger = 0, fun = 0, clean = 0 },
      digestion = 0, poopDueAt = nil, poopPendingWake = false,
      wastePresent = false, wasteCount = 0, wasteExposure = 0,
      wastePenalty = 0, devPoopQueued = false,
      dietStrain = 0, sicknessRisk = { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 },
      sickness = nil, sleepWalkIndex = nil,
      preferencesDiscovered = { favoriteFood = false, dislikedFood = false, favoriteGame = false },
      spriteStyle = NEO.normalizeNurserySpriteStyle(mon.species, mon.neoNurserySpriteStyle),
      nurseryMon = mon,
    }
    NEO.syncNurseryMonMetadata(baby, mon)
    return baby
  end

  local function slotLabel(slot)
    if type(slot) ~= "table" then return "NONE" end
    if slot.kind == "egg" then return "EGG" end
    return tostring(slot.nickname or slot.species or "BABY")
  end

  local function genderGlyph(gender)
    if gender == "male" then return "♂" end
    if gender == "female" then return "♀" end
    return ""
  end

  local function clampHappiness(v)
    v = math.floor(tonumber(v) or 0)
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return v
  end

  NEO.WEIGHT_PLAY_LOSS_TENTHS = 1      -- 0.1 lb per successful PLAY clear
  NEO.WEIGHT_MIN_RATIO = 0.85             -- exercise cannot go below 85% of species baseline

  NEO.COND_ROLL_SECONDS = 30 * 60        -- evaluate flavor COND twice per hour
  NEO.COND_ROLL_CHANCE = 0.50             -- average successful reroll ~once per hour
  NEO.COND_INFLUENCE_SECONDS = 30 * 60    -- recent care can bias the next roll

  function NEO.baseWeightTenths(species)
    local def = BABY_DEFS[species]
    return math.max(1, math.floor(tonumber(def and def.baseWeightTenths) or 1))
  end

  function NEO.minimumWeightTenths(species)
    return math.max(1, math.ceil(NEO.baseWeightTenths(species) * NEO.WEIGHT_MIN_RATIO))
  end

  function NEO.applyPlayWeightLoss(slot)
    if type(slot) ~= "table" or slot.kind ~= "baby" then return 0 end
    local current = math.max(1, math.floor(tonumber(slot.weightTenths)
      or NEO.baseWeightTenths(slot.species)))
    local floorWeight = NEO.minimumWeightTenths(slot.species)
    local after = math.max(floorWeight, current - NEO.WEIGHT_PLAY_LOSS_TENTHS)
    slot.weightTenths = after
    return current - after
  end

  function NEO.weightMovementScale(slot)
    if type(slot) ~= "table" or slot.kind ~= "baby" then return 1 end
    local base = NEO.baseWeightTenths(slot.species)
    local current = math.max(1, tonumber(slot.weightTenths) or base)
    local ratio = current / base

    -- Weight is intentionally only a tiny visual influence. At the exercise
    -- floor a baby is ~4% quicker; even a very heavy baby is capped at ~6%
    -- slower. Species personality remains by far the dominant movement factor.
    local scale = 1 + (ratio - 1) * 0.25
    return math.max(0.96, math.min(1.06, scale))
  end

  function NEO.normalizeNurserySpriteStyle(species, style)
    if OFFICIAL_BABY_SPECIES[species] == true then
      return style == "nursery" and "nursery" or "crystal"
    end
    return "nursery"
  end

  function NEO.nurseryFriendshipFromMon(mon)
    if type(mon) ~= "table" then return 0 end
    if mon.neoNurseryFriendship ~= nil then
      return clampHappiness(mon.neoNurseryFriendship)
    end
    -- Compatibility for older adopted records: convert the real Gen II
    -- happiness byte back onto Neo Nursery's visible 0-100 scale.
    local hidden = math.max(0, math.min(255, math.floor(tonumber(mon.happiness) or 120)))
    local visible = math.floor(((hidden - 120) / (255 - 120)) * 100 + 0.5)
    return clampHappiness(visible)
  end

  function NEO.syncNurseryMonMetadata(slot, mon)
    if type(slot) ~= "table" or type(mon) ~= "table" then return end
    local friendship = clampHappiness(slot.happiness or 0)
    local style = NEO.normalizeNurserySpriteStyle(slot.species or mon.species, slot.spriteStyle)
    slot.spriteStyle = style

    mon.neoNurseryRaised = true
    mon.neoNurseryFriendship = friendship
    mon.neoNurseryWeightTenths = math.max(1, math.floor(tonumber(slot.weightTenths)
      or NEO.baseWeightTenths(slot.species or mon.species)))
    mon.neoNurserySpriteStyle = style

    -- Visible Neo Nursery Friendship now backs the actual Gen II happiness
    -- byte: a fresh 0 begins at the normal hatch value 120 and 100 reaches 255.
    -- Crystal's friendship-evolution threshold is 220, so a fully bonded baby
    -- is genuinely evolution-ready after it leaves the Nursery.
    local hidden = math.floor(120 + (friendship / 100) * (255 - 120) + 0.5)
    mon.happiness = math.max(0, math.min(255, hidden))

    -- Cut babies now use EVOLVE_HAPPINESS. Keep already-raised/adopted records
    -- compatible when they pass back through Nursery metadata sync.
    if NEO.species[mon.species] == true and friendship >= 100 then
      mon.happiness = math.max(220, mon.happiness)
    end
  end

  local function normalizeWellnessState(t)
    if type(t) ~= "table" then return end
    t.dietStrain = math.max(0, tonumber(t.dietStrain) or 0)
    if type(t.sicknessRisk) ~= "table" then t.sicknessRisk = {} end

    -- BORED used to be a medicine-driven sickness. It is now a normal low-FUN
    -- COND, so old saves migrate that medical state/risk to FEVERISH instead.
    if t.sicknessRisk.feverish == nil and t.sicknessRisk.feverish ~= nil then
      t.sicknessRisk.feverish = tonumber(t.sicknessRisk.feverish) or 0
    end
    t.sicknessRisk.feverish = nil

    for _, kind in ipairs(SICKNESS_KINDS) do
      t.sicknessRisk[kind] = math.max(0, tonumber(t.sicknessRisk[kind]) or 0)
    end
    local sick = t.sickness
    if type(sick) == "table" and sick.kind == "bored" then
      sick.kind = "feverish"
    end
    if type(sick) ~= "table" or type(sick.kind) ~= "string" then
      t.sickness = nil
      return
    end
    if not SICKNESS_LABELS[sick.kind] then
      t.sickness = nil
      return
    end
    sick.severity = math.max(1, math.min(2, math.floor(tonumber(sick.severity) or 1)))
    sick.correctDoses = math.max(0, math.floor(tonumber(sick.correctDoses) or 0))
    sick.totalDoses = math.max(0, math.floor(tonumber(sick.totalDoses) or 0))
    t.sickness = sick
  end

  local function randomSicknessSeverity()
    if love.math and love.math.random then return love.math.random(1, 2) end
    return math.random(1, 2)
  end

  local function sicknessLabel(kind)
    return SICKNESS_LABELS[kind] or "NONE"
  end

  local function sicknessThoughtKind(kind)
    return SICKNESS_THOUGHTS[kind]
  end

  local function medicineIsCorrect(medicineId, sicknessKind)
    if medicineId == "FULL_HEAL" then return true end
    for _, def in ipairs(MEDICINE_DEFS) do
      if def.id == medicineId then return def.cures == sicknessKind end
    end
    return false
  end

  local function startSickness(t, kind)
    if type(t) ~= "table" then return false end
    normalizeWellnessState(t)
    if t.sickness then return false end
    if not SICKNESS_LABELS[kind] then return false end
    t.sickness = {
      kind = kind,
      severity = randomSicknessSeverity(),
      correctDoses = 0,
      totalDoses = 0,
    }
    return true
  end

  local function advanceSicknessRisks(t, elapsed)
    if type(t) ~= "table" then return end
    normalizeWellnessState(t)
    local hours = math.max(0, tonumber(elapsed) or 0) / 3600
    if hours <= 0 then return end

    local risk = t.sicknessRisk
    local hunger = clampMeter(t.hunger)
    local fun = clampMeter(t.fun)
    local clean = clampMeter(t.clean)
    local wasteCount = math.max(0, math.min(WASTE_MAX,
      math.floor(tonumber(t.wasteCount) or (t.wastePresent and 1 or 0))))

    -- Rich food strain fades slowly with time, but repeated heavy treats can
    -- still stack fast enough to cause a tummyache.
    t.dietStrain = math.max(0, t.dietStrain - hours * 0.06)

    local function adjust(kind, delta)
      risk[kind] = math.max(0, math.min(1.5, (tonumber(risk[kind]) or 0) + delta))
    end

    if t.sickness then
      for _, kind in ipairs(SICKNESS_KINDS) do adjust(kind, -hours * 0.04) end
      return
    end

    if t.dietStrain >= 1 then
      startSickness(t, "tummyache")
      t.dietStrain = math.max(0, t.dietStrain - 1)
      return
    end

    if hunger <= 0 then adjust("famished", hours * 0.40)
    elseif hunger <= 1 then adjust("famished", hours * 0.18)
    else adjust("famished", -hours * 0.10) end

    -- Low FUN by itself now means BORED and is fixed by PLAY. FEVERISH is a
    -- true medical condition caused by broader neglect instead: multiple care
    -- needs staying low at once, especially with waste in the room.
    local stress = 0
    if hunger <= 1 then stress = stress + 1 end
    if fun <= 1 then stress = stress + 1 end
    if clean <= 1 then stress = stress + 1 end
    if wasteCount >= 1 then stress = stress + 1 end
    if stress >= 3 then
      adjust("feverish", hours * 0.38)
    elseif stress == 2 then
      adjust("feverish", hours * 0.20)
    elseif stress == 1 then
      adjust("feverish", hours * 0.03)
    else
      adjust("feverish", -hours * 0.12)
    end

    local rashDelta = -hours * 0.08
    if clean <= 0 then rashDelta = rashDelta + hours * 0.42
    elseif clean <= 1 then rashDelta = rashDelta + hours * 0.24
    elseif clean <= 2 then rashDelta = rashDelta + hours * 0.10 end
    if wasteCount >= 1 then rashDelta = rashDelta + hours * (0.08 * wasteCount) end
    adjust("rash", rashDelta)

    local priorities = { "rash", "famished", "feverish" }
    for _, kind in ipairs(priorities) do
      if (tonumber(risk[kind]) or 0) >= 1 then
        startSickness(t, kind)
        risk[kind] = 0
        return
      end
    end
  end

  local function saveState()
    -- Gen1Recomp API 2 persists mod state through mod.save:get/set.  Earlier
    -- prototypes attached a table directly to mod.save, which survived only
    -- for the current Lua lifetime.  Migrate that table opportunistically if
    -- a hot-reload still has it, then keep the canonical state in save.modData.
    local s = mod.save:get("babycare", nil)
    local createdFresh = false
    if type(s) ~= "table" then
      local legacy = mod.save.babycare
      if type(legacy) == "table" then
        s = legacy
      else
        s = {}
        createdFresh = true
      end
      mod.save:set("babycare", s)
    end
    -- A completely fresh v0.0.26 install starts with an EMPTY Nursery so the
    -- Zelda introduction can actually lead into the player's first Odd Egg.
    -- Any state carrying fields from the older prototype is treated as legacy
    -- and still receives the BARIRIINA slot migration below.
    local hadPrototypeState = s.hunger ~= nil or s.roomIndex ~= nil
      or s.foodTestHungerV009 ~= nil or s.slotStateVersion ~= nil
      or s.eggClaims ~= nil or s.careClockVersion ~= nil

    if s.hunger == nil then s.hunger = 4 end
    if s.fun == nil then s.fun = 4 end
    if s.clean == nil then s.clean = 4 end
    if s.roomIndex == nil then s.roomIndex = 1 end
    if s.roomCycle == nil then s.roomCycle = 0 end
    if s.lightsOn == nil then s.lightsOn = true end
    if s.carePaused == nil then s.carePaused = false end
    if s.sleepGoodSeconds == nil then s.sleepGoodSeconds = 0 end
    if s.sleepWasWindow == nil then s.sleepWasWindow = false end
    if s.sleepWalkIndex ~= nil then s.sleepWalkIndex = math.floor(tonumber(s.sleepWalkIndex) or 0) end
    if s.pausedBabyWalkIndex ~= nil then
      s.pausedBabyWalkIndex = math.max(1, math.min(#BABY_WALK,
        math.floor(tonumber(s.pausedBabyWalkIndex) or 1)))
    end
    if s.wastePresent == nil then s.wastePresent = false end
    if s.wasteCount == nil then s.wasteCount = s.wastePresent == true and 1 or 0 end
    s.wasteCount = math.max(0, math.min(3, math.floor(tonumber(s.wasteCount) or 0)))
    s.wastePresent = s.wasteCount > 0
    if s.wasteExposure == nil then s.wasteExposure = 0 end
    if s.wastePenalty == nil then s.wastePenalty = 0 end
    if s.digestion == nil then s.digestion = 0 end
    if s.poopDueAt ~= nil then s.poopDueAt = tonumber(s.poopDueAt) end
    if s.poopPendingWake == nil then s.poopPendingWake = false end
    s.poopPendingWake = s.poopPendingWake == true
    if s.devPoopQueued == nil then s.devPoopQueued = false end
    if s.dietStrain == nil then s.dietStrain = 0 end
    normalizeWellnessState(s)
    if type(s.careRemainder) ~= "table" then s.careRemainder = {} end
    if s.careRemainder.hunger == nil then s.careRemainder.hunger = 0 end
    if s.careRemainder.fun == nil then s.careRemainder.fun = 0 end
    if s.careRemainder.clean == nil then s.careRemainder.clean = 0 end

    -- v0.0.17 slot migration. Preserve the old prototype BARIRIINA only for
    -- an EXISTING prototype save. Brand-new v0.0.26 players begin with all
    -- three slots empty and meet Zelda before receiving their first Odd Egg.
    if type(s.slots) ~= "table" then
      s.slots = {}
      if hadPrototypeState and not createdFresh then
        local first = cloneBabyDef("BARIRINA")
        first.hunger = clampMeter(s.hunger)
        first.fun = clampMeter(s.fun)
        first.clean = clampMeter(s.clean)
        first.careRemainder = {
          hunger = tonumber(s.careRemainder.hunger) or 0,
          fun = tonumber(s.careRemainder.fun) or 0,
          clean = tonumber(s.careRemainder.clean) or 0,
        }
        first.wastePresent = s.wastePresent == true
        first.wasteCount = math.max(0, math.min(3, math.floor(tonumber(s.wasteCount) or (s.wastePresent and 1 or 0))))
        first.wasteExposure = tonumber(s.wasteExposure) or 0
        first.wastePenalty = tonumber(s.wastePenalty) or 0
        first.digestion = tonumber(s.digestion) or 0
        first.poopDueAt = tonumber(s.poopDueAt)
        first.poopPendingWake = s.poopPendingWake == true
        first.devPoopQueued = s.devPoopQueued == true
        first.dietStrain = tonumber(s.dietStrain) or 0
        first.sicknessRisk = s.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
        first.sickness = s.sickness
        normalizeWellnessState(first)
        s.slots[1] = first
      end
      s.activeSlot = 1
    end
    if tonumber(s.activeSlot) == nil then s.activeSlot = 1 end
    s.activeSlot = math.max(1, math.min(SLOT_COUNT, math.floor(s.activeSlot)))
    if s.lastEggClaimRealAt == nil then s.lastEggClaimRealAt = 0 end
    if s.eggClaims == nil then s.eggClaims = 0 end
    if s.forceNextShinyEgg ~= true then s.forceNextShinyEgg = false end
    if type(s.unlockedEggs) ~= "table" then s.unlockedEggs = {} end
    if type(s.adoptedSpecies) ~= "table" then s.adoptedSpecies = {} end
    if type(s.unlockedNeoBabies) ~= "table" then s.unlockedNeoBabies = {} end
    if type(s.friendshipMasteredSpecies) ~= "table" then s.friendshipMasteredSpecies = {} end
    if type(s.friendshipMilestones) ~= "table" then s.friendshipMilestones = {} end
    if s.friendshipEverstoneGiftClaimed == nil then s.friendshipEverstoneGiftClaimed = false end
    if s.friendshipEverstoneGiftPending == nil then s.friendshipEverstoneGiftPending = false end

    -- Migrate the prototype's longer Baririina spelling and any cut-species
    -- unlock flags into Neo Nursery's permanent discovery table. Official-baby
    -- entries from the old 100-Friendship egg system are intentionally ignored.
    if s.unlockedEggs.BARIRIINA == true then s.unlockedNeoBabies.BARIRINA = true end
    for _, id in ipairs(NEO.pool) do
      if s.unlockedEggs[id] == true then s.unlockedNeoBabies[id] = true end
    end
    -- v0.0.69 retires the old guaranteed-next-Odd-Egg queue. Every unlocked
    -- Neo species is now its own permanent choice under CARE -> NEW EGG.
    s.guaranteedNeoEggs = {}
    s.nextGuaranteedEgg = nil
    if s.zeldaIntroduced == nil then s.zeldaIntroduced = false end
    if s.zeldaAccepted == nil then s.zeldaAccepted = false end
    if s.zeldaTutorialSeen == nil then s.zeldaTutorialSeen = false end
    if s.zeldaIntroAwaitingEgg == nil then s.zeldaIntroAwaitingEgg = false end
    if s.zeldaTutorialFinishing == nil then s.zeldaTutorialFinishing = false end
    if type(s.zeldaCareTipsSeen) ~= "table" then s.zeldaCareTipsSeen = {} end
    if s.zeldaPendingTip ~= nil then s.zeldaPendingTip = tostring(s.zeldaPendingTip) end
    local cleanMilestones = {}
    for _, event in ipairs(s.friendshipMilestones or {}) do
      if type(event) == "table" then
        local species = tostring(event.species or "")
        local neoUnlock = event.neoUnlock and tostring(event.neoUnlock) or nil
        if species ~= "" then
          if neoUnlock == "BARIRIINA" then neoUnlock = "BARIRINA" end
          if neoUnlock and not NEO.species[neoUnlock] then neoUnlock = nil end
          cleanMilestones[#cleanMilestones + 1] = { species = species, neoUnlock = neoUnlock }
        end
      end
    end
    s.friendshipMilestones = cleanMilestones
    if #cleanMilestones > 0 then s.zeldaPendingTip = "friendship" end
    if s.callPendingContact ~= nil then
      s.callPendingContact = tostring(s.callPendingContact)
      if s.callPendingContact ~= "zelda" then s.callPendingContact = nil end
    end
    if s.hasBabyMonitor == nil then
      local occupied = false
      for i = 1, SLOT_COUNT do if s.slots[i] then occupied = true break end end
      -- Existing dev saves already had remote Nursery access. Preserve that
      -- access; only a truly fresh empty Nursery waits for Zelda to award it.
      s.hasBabyMonitor = (not createdFresh) or occupied or s.zeldaAccepted == true
    end

    -- v0.0.9 food-system test migration only applies to an actual active baby.
    -- A fresh empty Nursery keeps a full/quiet HUD until the first hatch.
    if not s.foodTestHungerV009 then
      local active = s.slots[s.activeSlot]
      if active and active.kind == "baby" then s.hunger = 3 end
      s.foodTestHungerV009 = true
    end

    s.hunger = clampMeter(s.hunger)
    s.fun = clampMeter(s.fun)
    s.clean = clampMeter(s.clean)

    if tonumber(s.slotStateVersion) ~= 1 then
      local active = s.slots[s.activeSlot]
      if type(active) == "table" and active.kind == "baby" then
        active.hunger = s.hunger
        active.fun = s.fun
        active.clean = s.clean
        active.careRemainder = {
          hunger = tonumber(s.careRemainder.hunger) or 0,
          fun = tonumber(s.careRemainder.fun) or 0,
          clean = tonumber(s.careRemainder.clean) or 0,
        }
        active.wastePresent = s.wastePresent == true
        active.wasteCount = math.max(0, math.min(3, math.floor(tonumber(s.wasteCount) or (s.wastePresent and 1 or 0))))
        active.wasteExposure = tonumber(s.wasteExposure) or 0
        active.wastePenalty = tonumber(s.wastePenalty) or 0
        active.digestion = tonumber(s.digestion) or 0
        active.poopDueAt = tonumber(s.poopDueAt)
        active.poopPendingWake = s.poopPendingWake == true
        active.devPoopQueued = s.devPoopQueued == true
        active.dietStrain = tonumber(s.dietStrain) or 0
        active.sicknessRisk = s.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
        active.sickness = s.sickness
        normalizeWellnessState(active)
      end
      s.slotStateVersion = 1
    end

    local careClockVersion = math.floor(tonumber(s.careClockVersion) or 0)
    if careClockVersion < 1 then
      -- Legacy saves predating the real-time care clock start fresh rather
      -- than receiving retroactive meter loss from an unknown timestamp.
      s.careLastRealAt = wallNow()
      s.careRemainder.hunger = 0
      s.careRemainder.fun = 0
      s.careRemainder.clean = 0
    elseif tonumber(s.careLastRealAt) == nil then
      s.careLastRealAt = wallNow()
    end
    -- v0.0.98 makes the per-resident clock authoritative. Keep the global
    -- fields only as a mirror of the selected slot for UI/back-compat.
    s.careClockVersion = 2

    -- Waste/digestion v0.0.49 migration. Every baby owns its own hidden
    -- digestion clock and up to three persistent waste piles.
    local migrationNow = wallNow()
    for slotIndex, slot in ipairs(s.slots or {}) do
      if type(slot) == "table" then
        if slot.species == "BARIRIINA" then slot.species = "BARIRINA" end
        if slot.hatchSpecies == "BARIRIINA" then slot.hatchSpecies = "BARIRINA" end
        if slot.sourceSpecies == "BARIRIINA" then slot.sourceSpecies = "BARIRINA" end
        if slot.nickname == "BARIRIINA" then slot.nickname = "BARIRINA" end
        if type(slot.nurseryMon) == "table" and slot.nurseryMon.species == "BARIRIINA" then
          slot.nurseryMon.species = "BARIRINA"
          if slot.nurseryMon.name == "BARIRIINA" then slot.nurseryMon.name = "BARIRINA" end
          if slot.nurseryMon.nickname == "BARIRIINA" then slot.nurseryMon.nickname = "BARIRINA" end
        end
      end
      if type(slot) == "table" and slot.kind == "baby" then
        -- v0.0.95: each resident owns its own real-time care checkpoint. Older
        -- builds only tracked the currently selected slot, which meant an
        -- inactive resident could sit for hours and return with full meters.
        -- Preserve the old global checkpoint for the active baby; start other
        -- legacy residents at migration time so the fix does not retroactively
        -- punish them for time that old builds intentionally froze.
        if tonumber(slot.careLastRealAt) == nil then
          if slotIndex == s.activeSlot and tonumber(s.careLastRealAt) ~= nil then
            slot.careLastRealAt = tonumber(s.careLastRealAt)
          else
            slot.careLastRealAt = migrationNow
          end
        end
        if slot.sleepGoodSeconds == nil then
          slot.sleepGoodSeconds = (slotIndex == s.activeSlot) and math.max(0, tonumber(s.sleepGoodSeconds) or 0) or 0
        end
        slot.sleepGoodSeconds = math.max(0, tonumber(slot.sleepGoodSeconds) or 0)
        if slot.sleepWasWindow == nil then
          slot.sleepWasWindow = (slotIndex == s.activeSlot) and (s.sleepWasWindow == true) or false
        end
        slot.sleepWasWindow = slot.sleepWasWindow == true
        if slot.digestion == nil then slot.digestion = 0 end
        slot.digestion = math.max(0, tonumber(slot.digestion) or 0)
        if slot.poopDueAt ~= nil then slot.poopDueAt = tonumber(slot.poopDueAt) end
        if slot.poopPendingWake == nil then slot.poopPendingWake = false end
        slot.poopPendingWake = slot.poopPendingWake == true
        if slot.wasteCount == nil then slot.wasteCount = slot.wastePresent == true and 1 or 0 end
        slot.wasteCount = math.max(0, math.min(3, math.floor(tonumber(slot.wasteCount) or 0)))
        slot.wastePresent = slot.wasteCount > 0
        slot.wasteExposure = math.max(0, tonumber(slot.wasteExposure) or 0)
        slot.wastePenalty = math.max(0, tonumber(slot.wastePenalty) or 0)
        slot.devPoopQueued = slot.devPoopQueued == true
        if slot.sleepWalkIndex ~= nil then slot.sleepWalkIndex = math.floor(tonumber(slot.sleepWalkIndex) or 0) end
        if slot.conditionAmbient == nil and slot.conditionMood ~= nil then
          slot.conditionAmbient = tostring(slot.conditionMood)
        elseif slot.conditionAmbient ~= nil then
          slot.conditionAmbient = tostring(slot.conditionAmbient)
        end
        slot.conditionMood = nil
        slot.conditionUntilAt = nil

        if slot.conditionNextRollAt == nil then
          slot.conditionNextRollAt = migrationNow + NEO.COND_ROLL_SECONDS
        else
          slot.conditionNextRollAt = tonumber(slot.conditionNextRollAt)
        end
        if slot.conditionInfluence ~= nil then
          slot.conditionInfluence = tostring(slot.conditionInfluence)
        end
        if slot.conditionInfluenceUntilAt ~= nil then
          slot.conditionInfluenceUntilAt = tonumber(slot.conditionInfluenceUntilAt)
        end
        slot.conditionForceRoll = slot.conditionForceRoll == true
        slot.playLossStreak = math.max(0, math.floor(tonumber(slot.playLossStreak) or 0))
        if type(slot.preferencesDiscovered) ~= "table" then slot.preferencesDiscovered = {} end
        if OFFICIAL_BABY_SPECIES[slot.species] == true then
          -- Official babies hatch in their retail Crystal artwork. The cut /
          -- prototype NEO style is the max-Friendship reward, so unmastered
          -- residents from older dev builds are migrated back to CRYSTAL.
          local mastered = s.friendshipMasteredSpecies and s.friendshipMasteredSpecies[slot.species] == true
          if not mastered then
            slot.spriteStyle = "crystal"
          elseif slot.spriteStyle ~= "crystal" and slot.spriteStyle ~= "nursery" then
            slot.spriteStyle = "crystal"
          end
        elseif slot.spriteStyle ~= "crystal" then
          slot.spriteStyle = "nursery"
        end
        if type(slot.nurseryMon) == "table" then NEO.ensureNurseryRandomTypes(mod.game, slot.nurseryMon) end
        slot.preferencesDiscovered.favoriteFood = slot.preferencesDiscovered.favoriteFood == true
        slot.preferencesDiscovered.dislikedFood = slot.preferencesDiscovered.dislikedFood == true
        slot.preferencesDiscovered.favoriteGame = slot.preferencesDiscovered.favoriteGame == true
        normalizeWellnessState(slot)
      end
    end
    normalizeWellnessState(s)

    return s
  end

  local function firstOpenNurserySlot(s)
    s.slots = s.slots or {}
    for i = 1, SLOT_COUNT do
      if not s.slots[i] then return i end
    end
    return nil
  end

  local function copySlotToTopLevel(s, index)
    local slot = s.slots and s.slots[index]
    s.activeSlot = index or 1
    if slot and slot.kind == "baby" then
      s.hunger = clampMeter(slot.hunger == nil and 4 or slot.hunger)
      s.fun = clampMeter(slot.fun == nil and 4 or slot.fun)
      s.clean = clampMeter(slot.clean == nil and 4 or slot.clean)
      s.careRemainder = slot.careRemainder or { hunger = 0, fun = 0, clean = 0 }
      s.wasteCount = math.max(0, math.min(3, math.floor(tonumber(slot.wasteCount) or (slot.wastePresent and 1 or 0))))
      s.wastePresent = s.wasteCount > 0
      s.wasteExposure = math.max(0, tonumber(slot.wasteExposure) or 0)
      s.wastePenalty = tonumber(slot.wastePenalty) or 0
      s.digestion = math.max(0, tonumber(slot.digestion) or 0)
      s.poopDueAt = tonumber(slot.poopDueAt)
      s.poopPendingWake = slot.poopPendingWake == true
      s.devPoopQueued = slot.devPoopQueued == true
      s.dietStrain = tonumber(slot.dietStrain) or 0
      s.sicknessRisk = slot.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
      s.sickness = slot.sickness
      s.sleepWalkIndex = tonumber(slot.sleepWalkIndex)
      s.sleepGoodSeconds = math.max(0, tonumber(slot.sleepGoodSeconds) or 0)
      s.sleepWasWindow = slot.sleepWasWindow == true
      s.careLastRealAt = tonumber(slot.careLastRealAt) or wallNow()
      normalizeWellnessState(s)
    else
      -- Eggs and an empty Nursery have no active care needs.
      s.hunger, s.fun, s.clean = 4, 4, 4
      s.careRemainder = { hunger = 0, fun = 0, clean = 0 }
      s.wastePresent, s.wasteCount, s.wasteExposure, s.wastePenalty = false, 0, 0, 0
      s.digestion, s.poopDueAt, s.poopPendingWake, s.devPoopQueued = 0, nil, false, false
      s.dietStrain = 0
      s.sicknessRisk = { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
      s.sickness = nil
      s.sleepWalkIndex = nil
      s.sleepGoodSeconds = 0
      s.sleepWasWindow = false
      s.careLastRealAt = wallNow()
    end
  end

  local function nurseryEggMinutesForRecord(game, egg)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[egg and egg.species]
    local baseCycles = math.max(1, math.floor(tonumber(def and def.eggSteps) or tonumber(egg and egg.eggSteps) or 1))
    local remainingCycles = math.max(0, math.floor(tonumber(egg and egg.eggSteps) or baseCycles))
    if remainingCycles > baseCycles then remainingCycles = baseCycles end
    local minutes = EGG_HATCH_MINUTES * (remainingCycles / baseCycles)
    return minutes, remainingCycles, baseCycles
  end

  local function isEligiblePlayerEgg(game, mon)
    return Breeding.isEgg(mon) and OFFICIAL_BABY_SPECIES[mon.species] == true
  end

  function NEO.isEligibleOfficialQaBaby(mon)
    return type(mon) == "table" and not Breeding.isEgg(mon)
      and mon.neoNurseryQaOfficial == true and OFFICIAL_BABY_SPECIES[mon.species] == true
  end

  function NEO.isEligibleReturningBaby(mon)
    return type(mon) == "table" and not Breeding.isEgg(mon)
      and NEO.isNurseryBabySpecies(mon.species)
      and (mon.neoNurseryRaised == true
        or mon.babycareAdoptionMoves ~= nil
        or mon.babycareAdoptionMoveSource ~= nil
        or NEO.isEligibleOfficialQaBaby(mon))
  end

  local function eligiblePlayerEggRows(game)
    local save = game and game.save
    local rows = {}
    for i, mon in ipairs((save and save.party) or {}) do
      if isEligiblePlayerEgg(game, mon) then
        rows[#rows + 1] = {
          partyIndex = i,
          mon = mon,
          kind = "egg",
          nameLabel = zeldaTransferLabel("P" .. tostring(i) .. " EGG"),
          detailLabel = "",
        }
      elseif NEO.isEligibleReturningBaby(mon) then
        local glyph = genderGlyph(mon.gender)
        local level = math.max(1, math.floor(tonumber(mon.level) or 1))
        local detail = (glyph ~= "" and (glyph .. "  ") or "") .. "LV." .. tostring(level)
        rows[#rows + 1] = {
          partyIndex = i,
          mon = mon,
          kind = "baby",
          nameLabel = zeldaTransferLabel(tostring(mon.nickname or mon.species or "BABY")),
          detailLabel = zeldaTransferLabel(detail),
        }
      end
    end
    return rows
  end

  local function depositPlayerEgg(game, wantedPartyIndex)
    local save = game and game.save
    if not save then return false, "NO SAVE" end
    local s = saveState()
    local open = firstOpenNurserySlot(s)
    if not open then return false, "NO OPEN SLOT" end

    local partyIndex, egg, returningBaby
    if wantedPartyIndex ~= nil then
      local i = math.floor(tonumber(wantedPartyIndex) or 0)
      local mon = save.party and save.party[i]
      if mon and isEligiblePlayerEgg(game, mon) then partyIndex, egg = i, mon
      elseif mon and NEO.isEligibleReturningBaby(mon) then partyIndex, returningBaby = i, mon end
    else
      for i, mon in ipairs(save.party or {}) do
        if isEligiblePlayerEgg(game, mon) then partyIndex, egg = i, mon break
        elseif NEO.isEligibleReturningBaby(mon) then partyIndex, returningBaby = i, mon break end
      end
    end
    if not egg and not returningBaby then return false, "NO BABY EGG" end

    if returningBaby then
      -- Adopted/withdrawn Neo Nursery babies can return whenever a slot is
      -- available. Tagged official babies from older development saves share this path.
      table.remove(save.party, partyIndex)
      Mail.removeSlot(save, partyIndex)
      local resident = nurseryBabyFromMon(returningBaby, "player")
      if not resident then return false, "BAD BABY" end
      s.slots[open] = resident
      copySlotToTopLevel(s, open)
      mod.save:set("babycare", s)
      return true, open, "baby"
    end

    -- Remove the exact egg record from the party. Eggs cannot hold mail, but
    -- party mail slots behind it still need to shift with their owners.
    table.remove(save.party, partyIndex)
    Mail.removeSlot(save, partyIndex)

    local remainingMinutes, remainingCycles, baseCycles = nurseryEggMinutesForRecord(game, egg)
    local alreadyElapsed = math.max(0, EGG_HATCH_MINUTES - remainingMinutes)
    local gameNow, realNow = gameMinuteStamp(game), wallNow()
    s.slots[open] = {
      kind = "egg",
      origin = "player",
      sourceEgg = egg,
      sourceSpecies = egg.species,
      sourceEggStepsAtDeposit = remainingCycles,
      sourceEggBaseSteps = baseCycles,
      sourceRemainingMinutesAtDeposit = remainingMinutes,
      startedMinute = gameNow - alreadyElapsed,
      startedRealAt = realNow - math.floor(alreadyElapsed * 60),
      readyMinute = gameNow + remainingMinutes,
    }
    copySlotToTopLevel(s, open)
    mod.save:set("babycare", s)
    return true, open, "egg"
  end

  local function updateSourceEggProgressFromNursery(slot, game)
    if not (slot and slot.origin == "player" and type(slot.sourceEgg) == "table") then return end
    local startMinutes = tonumber(slot.sourceRemainingMinutesAtDeposit) or EGG_HATCH_MINUTES
    local startCycles = math.max(0, math.floor(tonumber(slot.sourceEggStepsAtDeposit) or tonumber(slot.sourceEgg.eggSteps) or 0))
    if startCycles <= 0 or startMinutes <= 0 then
      slot.sourceEgg.eggSteps = 0
      return
    end
    local gameNow = gameMinuteStamp(game)
    local startedGame = tonumber(slot.startedMinute) or gameNow
    local gameElapsed = math.max(0, gameNow - startedGame)
    local startedReal = tonumber(slot.startedRealAt) or wallNow()
    local realElapsed = math.max(0, wallNow() - startedReal) / 60
    local totalElapsed = math.max(gameElapsed, realElapsed)
    local elapsed = math.max(0, totalElapsed - (EGG_HATCH_MINUTES - startMinutes))
    local remainingMinutes = math.max(0, startMinutes - elapsed)
    local ratio = remainingMinutes / startMinutes
    slot.sourceEgg.eggSteps = math.max(0, math.ceil(startCycles * ratio))
  end

  local function withdrawablePlayerRows()
    local s = saveState()
    local rows = {}
    for i = 1, SLOT_COUNT do
      local slot = s.slots and s.slots[i]
      if slot and slot.origin == "player" then
        if slot.kind == "egg" then
          rows[#rows + 1] = {
            slotIndex = i, slot = slot,
            slotLabel = "SLOT " .. tostring(i),
            nameLabel = "EGG",
          }
        elseif slot.kind == "baby" and type(slot.nurseryMon) == "table" then
          rows[#rows + 1] = {
            slotIndex = i, slot = slot,
            slotLabel = "SLOT " .. tostring(i),
            nameLabel = zeldaTransferLabel(tostring(slot.nickname or slot.species or "BABY")),
          }
        end
      end
    end
    return rows
  end

  local function withdrawPlayerResident(game, wantedSlotIndex)
    local save = game and game.save
    if not save then return false, "NO SAVE" end
    if #(save.party or {}) >= 6 then return false, "PARTY FULL" end
    local s = saveState()
    local slotIndex
    local function eligible(slot)
      return slot and slot.origin == "player" and
        ((slot.kind == "egg" and type(slot.sourceEgg) == "table") or
         (slot.kind == "baby" and type(slot.nurseryMon) == "table"))
    end
    if wantedSlotIndex ~= nil then
      local i = math.floor(tonumber(wantedSlotIndex) or 0)
      if eligible(s.slots and s.slots[i]) then slotIndex = i end
    else
      local active = tonumber(s.activeSlot) or 1
      if eligible(s.slots and s.slots[active]) then slotIndex = active
      else
        for i = 1, SLOT_COUNT do if eligible(s.slots and s.slots[i]) then slotIndex = i break end end
      end
    end
    if not slotIndex then return false, "NO PLAYER MON" end

    local slot = s.slots[slotIndex]
    local record
    if slot.kind == "egg" then
      updateSourceEggProgressFromNursery(slot, game)
      record = slot.sourceEgg
    else
      record = slot.nurseryMon
      NEO.psRefreshMon(game, record, false)
      NEO.ensureNurseryRandomTypes(game, record)
      NEO.syncNurseryMonMetadata(slot, record)
    end
    save.party = save.party or {}
    save.party[#save.party + 1] = record
    s.slots[slotIndex] = nil

    local nextSlot
    for i = 1, SLOT_COUNT do if s.slots[i] then nextSlot = i break end end
    copySlotToTopLevel(s, nextSlot or 1)
    mod.save:set("babycare", s)
    return true, slotIndex, slot.kind
  end

  local function adoptableNurseryRows()
    local s = saveState()
    local rows, nurseryBabies = {}, 0
    for i = 1, SLOT_COUNT do
      local slot = s.slots and s.slots[i]
      if slot and slot.kind == "baby" and slot.origin ~= "player" then
        nurseryBabies = nurseryBabies + 1
        if clampHappiness(slot.happiness) >= 100 then
          rows[#rows + 1] = {
            slotIndex = i,
            slot = slot,
            slotLabel = "SLOT " .. tostring(i),
            nameLabel = zeldaTransferLabel(tostring(slot.nickname or slot.species or "BABY")),
          }
        end
      end
    end
    return rows, nurseryBabies
  end

  local function shuffledTwo(list)
    local pool = {}
    for _, value in ipairs(list or {}) do pool[#pool + 1] = value end
    for i = #pool, 2, -1 do
      local j
      if love.math and love.math.random then j = love.math.random(i) else j = math.random(i) end
      pool[i], pool[j] = pool[j], pool[i]
    end
    local out = {}
    if pool[1] then out[#out + 1] = pool[1] end
    if pool[2] then out[#out + 1] = pool[2] end
    return out
  end

  local function validUniqueMoves(game, list)
    local moves = game and game.data and game.data.moves or {}
    local out, seen = {}, {}
    for _, id in ipairs(list or {}) do
      if type(id) == "string" and moves[id] and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
    return out
  end

  local function adoptionBonusMoves(game, species)
    local special = validUniqueMoves(game, ADOPTION_SPECIAL_MOVES[species])
    if #special >= 2 then return shuffledTwo(special), "special" end
    local def = game and game.data and game.data.pokemon and game.data.pokemon[species]
    local eggs = validUniqueMoves(game, def and def.eggMoves)
    if #eggs >= 2 then return shuffledTwo(eggs), "egg" end
    -- A malformed or modded species should never block adoption. If fewer than
    -- two egg moves exist, grant whatever legitimate move data is available.
    return shuffledTwo(eggs), "egg"
  end

  local function knowsMove(mon, moveId)
    for _, move in ipairs(mon and mon.moves or {}) do
      if move and move.id == moveId then return true end
    end
    return false
  end

  local function adoptionMoveEntry(game, moveId)
    local def = game and game.data and game.data.moves and game.data.moves[moveId]
    local pp = def and tonumber(def.pp) or 0
    return { id = moveId, pp = pp, maxPp = pp }
  end

  local function grantAdoptionBonusMoves(game, mon)
    if type(mon) ~= "table" or not mon.species then return {} end
    local bonuses, source = adoptionBonusMoves(game, mon.species)
    mon.moves = mon.moves or {}
    local wanted = {}
    for _, id in ipairs(bonuses) do wanted[id] = true end

    for _, id in ipairs(bonuses) do
      if not knowsMove(mon, id) then
        mon.moves[#mon.moves + 1] = adoptionMoveEntry(game, id)
      end
      while #mon.moves > 4 do
        local removeAt
        for index, move in ipairs(mon.moves) do
          if not wanted[move and move.id] then removeAt = index break end
        end
        table.remove(mon.moves, removeAt or 1)
      end
    end
    mon.babycareAdoptionMoves = bonuses
    mon.babycareAdoptionMoveSource = source
    return bonuses
  end

  local function firstStorageBoxWithRoom(save)
    if not save then return nil end
    local current = math.floor(tonumber(save.currentBox) or 1)
    if current < 1 or current > Boxes.NUM_BOXES then current = 1 end
    for off = 0, Boxes.NUM_BOXES - 1 do
      local index = ((current - 1 + off) % Boxes.NUM_BOXES) + 1
      if not Boxes.isFull(save, index) then return index end
    end
    return nil
  end

  function NEO.unlockRandomCutBaby(s)
    if type(s) ~= "table" then return nil end
    s.unlockedNeoBabies = s.unlockedNeoBabies or {}
    local locked = {}
    for _, id in ipairs(NEO.pool) do
      if s.unlockedNeoBabies[id] ~= true then locked[#locked + 1] = id end
    end
    if #locked == 0 then return nil end
    local id = locked[NEO.randomIndex(#locked)]
    s.unlockedNeoBabies[id] = true
    -- Keep the legacy field mirrored for compatibility with earlier dev saves.
    s.unlockedEggs = s.unlockedEggs or {}
    s.unlockedEggs[id] = true
    return id
  end

  function NEO.noteFriendshipMilestone(s, slot)
    if type(s) ~= "table" or type(slot) ~= "table" or slot.kind ~= "baby" then return nil, false end
    local species = tostring(slot.species or "")
    if species == "" then return nil, false end
    s.friendshipMasteredSpecies = s.friendshipMasteredSpecies or {}
    if s.friendshipMasteredSpecies[species] == true then return nil, false end
    s.friendshipMasteredSpecies[species] = true

    local unlocked = NEO.unlockRandomCutBaby(s)
    s.friendshipMilestones = s.friendshipMilestones or {}
    s.friendshipMilestones[#s.friendshipMilestones + 1] = {
      species = species, neoUnlock = unlocked,
    }
    -- Friendship/adoption progression takes priority over routine care tips so
    -- Zelda's portrait immediately communicates the milestone in the Nursery.
    s.zeldaPendingTip = "friendship"
    return unlocked, true
  end

  local function adoptNurseryBaby(game, wantedSlotIndex)
    local save = game and game.save
    if not save then return false, "NO SAVE" end
    local s = saveState()
    local i = math.floor(tonumber(wantedSlotIndex) or 0)
    local slot = s.slots and s.slots[i]
    if not (slot and slot.kind == "baby" and slot.origin ~= "player") then
      return false, "NOT ADOPTABLE"
    end
    if clampHappiness(slot.happiness) < 100 then
      return false, "NEEDS 100 FRIENDSHIP"
    end

    -- Nursery-born babies carry their exact generated Gen II record from the
    -- hatch step. Older prototype residents may predate that field, so rebuild
    -- only as a compatibility fallback rather than making adoption impossible.
    local record = slot.nurseryMon
    if type(record) ~= "table" then
      record = newNurseryMon(game, slot.species, nil)
      if not record then return false, "NO POKEMON RECORD" end
    end

    local destination, detail, boxIndex
    save.party = save.party or {}
    if #save.party < Boxes.PARTY_SIZE then
      destination = "party"
    else
      boxIndex = firstStorageBoxWithRoom(save)
      if not boxIndex then return false, "STORAGE FULL" end
      destination, detail = "box", boxIndex
    end

    -- The 100-Friendship adoption reward is applied only after a receiving
    -- destination has been confirmed, so a failed full-storage attempt cannot
    -- mutate the Nursery resident. The exact DVs/shiny/gender/etc. record is
    -- otherwise untouched.
    NEO.psRefreshMon(game, record, true)
    NEO.ensureNurseryRandomTypes(game, record)
    NEO.syncNurseryMonMetadata(slot, record)
    grantAdoptionBonusMoves(game, record)
    if destination == "party" then
      save.party[#save.party + 1] = record
    else
      local box = Boxes.box(save, boxIndex)
      box[#box + 1] = record
      Boxes.enterBox(record, game.data)
    end

    -- Clear the Nursery only after the receiving destination succeeded. This
    -- makes the transfer one-way and prevents duplicate copies on a failed PC
    -- deposit or a repeated Zelda interaction.
    local adoptedSpecies = tostring(slot.species or record.species or "")
    s.slots[i] = nil
    s.adoptions = math.max(0, math.floor(tonumber(s.adoptions) or 0)) + 1

    -- Adoption history is still tracked, but Neo discovery now happens at the
    -- moment a unique species first reaches 100 Friendship. That lets Zelda
    -- announce both adoption readiness and the newly discovered Egg together.
    s.adoptedSpecies = s.adoptedSpecies or {}
    local firstUniqueSpecies = adoptedSpecies ~= "" and s.adoptedSpecies[adoptedSpecies] ~= true
    if firstUniqueSpecies then s.adoptedSpecies[adoptedSpecies] = true end
    local neoUnlock = nil

    local nextSlot
    for slotIndex = 1, SLOT_COUNT do
      if s.slots[slotIndex] then nextSlot = slotIndex break end
    end
    copySlotToTopLevel(s, nextSlot or 1)
    mod.save:set("babycare", s)
    return true, destination, detail, s.adoptions == 1, neoUnlock, firstUniqueSpecies
  end

  local function applyFriendshipDelta(s, slot, delta)
    if type(s) ~= "table" or type(slot) ~= "table" or slot.kind ~= "baby" then return 0, false end
    local before = clampHappiness(slot.happiness or 0)
    local after = clampHappiness(before + (tonumber(delta) or 0))
    slot.happiness = after
    NEO.syncNurseryMonMetadata(slot, slot.nurseryMon)
    local hit100 = before < 100 and after >= 100
    if hit100 then NEO.noteFriendshipMilestone(s, slot) end
    return after - before, hit100
  end

  local function advancePassiveFriendship(s, awakeElapsed)
    local slot = activeBabyRecord(s)
    if not (slot and slot.kind == "baby") then return false end
    local seconds = math.max(0, tonumber(awakeElapsed) or 0)
    if seconds <= 0 then return false end

    local rem = math.max(0, tonumber(slot.happinessRemainder) or 0) + seconds
    local steps = math.floor(rem / HAPPINESS_STEP_SECONDS)
    slot.happinessRemainder = rem - steps * HAPPINESS_STEP_SECONDS
    if steps <= 0 then return false end

    local crossed = false
    for _ = 1, steps do
      local h, f, c = clampMeter(s.hunger), clampMeter(s.fun), clampMeter(s.clean)
      local avg = (h + f + c) / 3
      local delta = 0
      if h == 0 or f == 0 or c == 0 then
        delta = -2
      elseif avg >= 3.5 then
        delta = 1
      elseif avg < 1.5 then
        delta = -1
      end
      local _, hit100 = applyFriendshipDelta(s, slot, delta)
      crossed = crossed or hit100
    end
    return crossed
  end

  -- PokeSurvive camping advances Crystal's displayed clock by eight hours in
  -- one instant. Care needs intentionally remain REAL-time systems, so a camp
  -- skip must never subtract eight hours of Hunger/Fun/Clean or manufacture
  -- eight hours of digestion. Sleep quality, however, belongs to the in-game
  -- day/night schedule. Reconcile only the skipped bedtime minutes here.
  local function advanceSyntheticSleepClock(s, game, startMinute, advanceMinutes)
    if type(s) ~= "table" or s.carePaused == true then return false end
    local slot = activeBabyRecord(s)
    if not (slot and slot.kind == "baby") then return false end

    local minutes = math.max(0, math.floor(tonumber(advanceMinutes) or 0))
    if minutes <= 0 then return false end
    -- Camping is eight hours today, but keep this defensive if another version
    -- supplies a larger forward skip. A week-sized jump is almost certainly a
    -- clock correction rather than a care event.
    minutes = math.min(minutes, 24 * 60)

    local startHour, wakeHour = sleepSchedule(slot.species)
    local cursor = math.floor(tonumber(startMinute) or currentGameMinuteOfDay(game)) % (24 * 60)
    local lightsOff = s.lightsOn == false
    s.sicknessRisk = s.sicknessRisk or {}
    local tiredRisk = math.max(0, tonumber(s.sicknessRisk.tired) or 0)
    local goodSeconds = math.max(0, tonumber(s.sleepGoodSeconds) or 0)
    local crossedFriendship = false

    local function inWindowAt(minute)
      return hourInWindow((minute % (24 * 60)) / 60, startHour, wakeHour)
    end

    for _ = 1, minutes do
      local inWindow = inWindowAt(cursor)
      local nextMinute = (cursor + 1) % (24 * 60)
      local nextInWindow = inWindowAt(nextMinute)

      if inWindow then
        s.sleepWasWindow = true
        if lightsOff then
          goodSeconds = goodSeconds + 60
          tiredRisk = math.max(0, tiredRisk - (0.20 / 60))
        else
          tiredRisk = math.min(1.5, tiredRisk + (0.11 / 60))
        end
      else
        tiredRisk = math.max(0, tiredRisk - (0.04 / 60))
      end

      -- Crossing the wake boundary resolves the night's sleep exactly once.
      if inWindow and not nextInWindow and s.sleepWasWindow == true then
        if goodSeconds >= GOOD_SLEEP_REWARD_SECONDS then
          local _, hit100 = applyFriendshipDelta(s, slot, GOOD_SLEEP_FRIENDSHIP)
          crossedFriendship = crossedFriendship or hit100
        end
        goodSeconds = 0
        s.sleepWasWindow = false
      end
      cursor = nextMinute
    end

    s.sleepGoodSeconds = goodSeconds
    s.sicknessRisk.tired = tiredRisk
    if not s.sickness and tiredRisk >= 1 then
      if startSickness(s, "tired") then s.sicknessRisk.tired = 0 end
    end

    -- Keep the resident's wellness copy coherent immediately after camp.
    slot.sicknessRisk = s.sicknessRisk
    slot.sickness = s.sickness
    normalizeWellnessState(slot)

    local nowInWindow = inWindowAt(cursor)
    -- Bedtime is also a one-time automatic tutorial. A later manual CALL may
    -- still remind the player about sleep when the baby is currently in-window.
    if type(s.zeldaCareTipsSeen) ~= "table" then s.zeldaCareTipsSeen = {} end
    if nowInWindow and s.zeldaPendingTip == nil and not s.zeldaCareTipsSeen.bedtime then
      s.zeldaPendingTip = "bedtime"
    end
    return crossedFriendship
  end

  local function advanceCareClock(s, suppliedNow, deferPoopAnimation, game)
    if type(s) ~= "table" then return 0, false end
    local beforeHunger = clampMeter(s.hunger)
    local beforeFun = clampMeter(s.fun)
    local beforeClean = clampMeter(s.clean)
    local beforeWaste = math.max(0, math.floor(tonumber(s.wasteCount) or (s.wastePresent and 1 or 0)))
    local hadSickness = type(s.sickness) == "table" and s.sickness.kind ~= nil
    local now = tonumber(suppliedNow) or wallNow()
    local last = tonumber(s.careLastRealAt) or now
    local elapsed = now - last

    -- A host clock moved backwards: do not create negative care time and do
    -- not preserve a future checkpoint that could freeze the nursery.
    if elapsed < 0 then elapsed = 0 end
    s.careLastRealAt = now

    -- PAUSE CARE discards elapsed care time completely, including passive
    -- Friendship checks, digestion, sleep accounting, and meter drain.
    if s.carePaused == true or elapsed <= 0 then return elapsed, false end

    local rem = s.careRemainder
    if type(rem) ~= "table" then
      rem = { hunger = 0, fun = 0, clean = 0 }
      s.careRemainder = rem
    end

    local timeline = careTimelineSegments(s, game, last, now)
    local sleepingSeconds, awakeSeconds = 0, 0
    for _, seg in ipairs(timeline) do
      if seg.sleeping then sleepingSeconds = sleepingSeconds + seg.seconds
      else awakeSeconds = awakeSeconds + seg.seconds end
    end

    -- Awake Hunger loses half a heart every 45 minutes and Fun every 75.
    -- Scheduled sleep counts at only one-sixth speed whether the light is on
  -- or off. LIGHTS OFF controls sleep quality/TIRED, not the metabolic slowdown.
  -- Species personality nudges
    -- the baseline +/-10% by scaling each interval, just as before.
    local active = activeBabyRecord(s)
    local personality = active and PERSONALITY_PROFILES[active.species] or nil
    local effectiveNeedSeconds = awakeSeconds + sleepingSeconds * SLEEP_CARE_DRAIN_FACTOR
    local function drain(name)
      local rate = personality and tonumber(personality[name .. "Rate"]) or 1
      if not rate or rate <= 0 then rate = 1 end
      local interval = CARE_HALF_HEART_SECONDS[name] / rate
      local total = math.max(0, tonumber(rem[name]) or 0) + effectiveNeedSeconds
      local steps = math.floor(total / interval)
      rem[name] = total - steps * interval
      if steps > 0 then s[name] = clampMeter((s[name] or 0) - steps * 0.5) end
    end
    drain("hunger")
    drain("fun")

    local function poopDelay()
      if love.math and love.math.random then
        return love.math.random(POOP_DELAY_MIN_SECONDS, POOP_DELAY_MAX_SECONDS)
      end
      return math.random(POOP_DELAY_MIN_SECONDS, POOP_DELAY_MAX_SECONDS)
    end

    -- Digestion keeps moving during sleep, but a sleeping Babymon never poops.
    -- If digestion fills (or an already-scheduled poop comes due) while asleep,
    -- hold exactly ONE pending bowel movement. Its normal 1-5 minute timer
    -- starts only after the baby wakes. Existing waste still dirties the room
    -- overnight, so putting a baby to bed in a dirty Nursery still matters.
    local wasteCount = math.max(0, math.min(WASTE_MAX,
      math.floor(tonumber(s.wasteCount) or (s.wastePresent and 1 or 0))))
    local exposure = math.max(0, tonumber(s.wasteExposure) or 0)
    local digestion = math.max(0, tonumber(s.digestion) or 0)
    local dueAt = tonumber(s.poopDueAt)
    local pendingWake = s.poopPendingWake == true
    local passiveRate = 1 / DIGESTION_FULL_SECONDS
    local guard = 0

    local function resolvePoop()
      local beforeCleanNow = clampMeter(s.clean)
      s.clean = clampMeter(beforeCleanNow - 1)
      s.wastePenalty = math.max(0, tonumber(s.wastePenalty) or 0) + (beforeCleanNow - s.clean)
      wasteCount = wasteCount + 1
      digestion = math.max(0, digestion - 1)
      dueAt = nil
      pendingWake = false
      guard = guard + 1
    end

    for _, seg in ipairs(timeline) do
      local segStart = tonumber(seg.startAt) or last
      local segEnd = tonumber(seg.endAt) or segStart
      local segSeconds = math.max(0, tonumber(seg.seconds) or (segEnd - segStart))
      if segSeconds > 0 then
        if wasteCount >= WASTE_MAX then
          exposure = exposure + segSeconds * wasteCount
          digestion = math.min(1, digestion + segSeconds * passiveRate)
          dueAt = nil
          pendingWake = false
        elseif seg.sleeping then
          exposure = exposure + segSeconds * wasteCount
          digestion = math.min(1, digestion + segSeconds * passiveRate)
          if dueAt ~= nil or digestion >= 1 then pendingWake = true end
          dueAt = nil
        else
          local t = segStart
          if pendingWake and wasteCount < WASTE_MAX then
            digestion = math.max(1, digestion)
            dueAt = t + poopDelay()
            pendingWake = false
          end

          while t < segEnd and guard < 32 and wasteCount < WASTE_MAX do
            if dueAt == nil then
              if digestion >= 1 then
                dueAt = t + poopDelay()
              else
                local thresholdAt = t + (1 - digestion) / passiveRate
                if thresholdAt > segEnd then
                  local dt = segEnd - t
                  exposure = exposure + dt * wasteCount
                  digestion = digestion + dt * passiveRate
                  t = segEnd
                  break
                end
                local dt = thresholdAt - t
                exposure = exposure + dt * wasteCount
                digestion = 1
                t = thresholdAt
                dueAt = t + poopDelay()
              end
            end

            if dueAt > segEnd then
              local dt = segEnd - t
              exposure = exposure + dt * wasteCount
              digestion = digestion + dt * passiveRate
              t = segEnd
              break
            end

            -- While the Nursery is visibly open, leave a newly due poop queued
            -- for the live ANGRY/shake/Octazooka animation instead of silently
            -- resolving it in this clock pass.
            if deferPoopAnimation == true and segEnd >= now and dueAt <= now then
              local dt = segEnd - t
              exposure = exposure + dt * wasteCount
              digestion = digestion + dt * passiveRate
              t = segEnd
              break
            end

            local dt = math.max(0, dueAt - t)
            exposure = exposure + dt * wasteCount
            digestion = digestion + dt * passiveRate
            t = math.max(t, dueAt)
            resolvePoop()
          end

          if wasteCount >= WASTE_MAX and t < segEnd then
            local dt = segEnd - t
            exposure = exposure + dt * wasteCount
            digestion = math.min(1, digestion + dt * passiveRate)
            dueAt = nil
            pendingWake = false
          end
        end
      end
    end

    local dirtySteps = math.floor(exposure / WASTE_CLEAN_DRAIN_SECONDS)
    s.wasteExposure = exposure - dirtySteps * WASTE_CLEAN_DRAIN_SECONDS
    if dirtySteps > 0 then
      s.clean = clampMeter((s.clean or 0) - dirtySteps * 0.5)
    end

    if wasteCount >= WASTE_MAX then
      digestion = math.min(digestion, 1)
      dueAt = nil
      pendingWake = false
    end
    s.wasteCount = wasteCount
    s.wastePresent = wasteCount > 0
    s.digestion = digestion
    s.poopDueAt = dueAt
    s.poopPendingWake = pendingWake
    advanceSicknessRisks(s, elapsed)

    -- TIRED uses the same reconstructed sleep timeline. Proper lights-off
    -- sleep clears fatigue; sleeping with the light left on builds it.
    -- At least six hours of real lights-off sleep still awards +2 Friendship
    -- once that sleep window has ended.
    s.sicknessRisk = s.sicknessRisk or {}
    local tiredRisk = math.max(0, tonumber(s.sicknessRisk.tired) or 0)
    for _, seg in ipairs(timeline) do
      local hours = math.max(0, tonumber(seg.seconds) or 0) / 3600
      if seg.inSleepWindow then
        s.sleepWasWindow = true
        if seg.properSleep then
          s.sleepGoodSeconds = math.max(0, tonumber(s.sleepGoodSeconds) or 0) + seg.seconds
          tiredRisk = math.max(0, tiredRisk - hours * 0.20)
        else
          -- The baby is still asleep with the light on, but the poor sleep
          -- builds TIRED risk until the player switches the room light off.
          tiredRisk = math.min(1.5, tiredRisk + hours * 0.11)
        end
      else
        tiredRisk = math.max(0, tiredRisk - hours * 0.04)
      end
    end

    local crossedFriendship = advancePassiveFriendship(s, awakeSeconds)
    local inSleepWindowNow = sleepWindowActiveFor(s, game)
    if not inSleepWindowNow and s.sleepWasWindow == true then
      local slot = activeBabyRecord(s)
      if slot and slot.kind == "baby"
          and (tonumber(s.sleepGoodSeconds) or 0) >= GOOD_SLEEP_REWARD_SECONDS then
        local _, hit100 = applyFriendshipDelta(s, slot, GOOD_SLEEP_FRIENDSHIP)
        crossedFriendship = crossedFriendship or hit100
      end
      s.sleepGoodSeconds = 0
      s.sleepWasWindow = false
    end

    s.sicknessRisk.tired = tiredRisk
    if not s.sickness and tiredRisk >= 1 then
      if startSickness(s, "tired") then s.sicknessRisk.tired = 0 end
    end

    -- Queue one-time tutorial hints for care mechanics. Once a specific
    -- gameplay concept has been explained, it never auto-prompts again on this
    -- save. Manual CALLs are separate and may still give live urgent-care help.
    if type(s.zeldaCareTipsSeen) ~= "table" then s.zeldaCareTipsSeen = {} end
    if s.zeldaPendingTip == nil then
      if inSleepWindowNow and not s.zeldaCareTipsSeen.bedtime then
        s.zeldaPendingTip = "bedtime"
      elseif not hadSickness and type(s.sickness) == "table" and s.sickness.kind ~= nil
          and not s.zeldaCareTipsSeen.sickness then
        s.zeldaPendingTip = "sickness"
      elseif math.max(0, math.floor(tonumber(s.wasteCount) or 0)) > beforeWaste
          and not s.zeldaCareTipsSeen.poop then
        s.zeldaPendingTip = "poop"
      elseif beforeHunger > 0 and clampMeter(s.hunger) == 0 and not s.zeldaCareTipsSeen.hunger then
        s.zeldaPendingTip = "hunger"
      elseif beforeFun > 0 and clampMeter(s.fun) == 0 and not s.zeldaCareTipsSeen.fun then
        s.zeldaPendingTip = "fun"
      elseif beforeClean > 0 and clampMeter(s.clean) == 0 and not s.zeldaCareTipsSeen.clean then
        s.zeldaPendingTip = "clean"
      end
    end

    return elapsed, crossedFriendship
  end

  -- v0.0.98: each occupied Nursery slot owns its own real-time care
  -- state. The selected slot is mirrored into the legacy top-level fields only
  -- for rendering/menu compatibility; no resident depends on another slot's
  -- checkpoint anymore.
  local function advanceResidentCareSlot(s, slotIndex, suppliedNow, deferPoopAnimation, game)
    if type(s) ~= "table" or type(s.slots) ~= "table" then return 0, false end
    local slot = s.slots[slotIndex]
    if not (slot and slot.kind == "baby") then return 0, false end
    local now = tonumber(suppliedNow) or wallNow()

    -- Routine Zelda care hints belong to the visible resident. Inactive babies
    -- still live normally, but do not hijack the active slot's help portrait.
    local activeIndex = math.max(1, math.min(SLOT_COUNT, math.floor(tonumber(s.activeSlot) or 1)))
    local isActive = slotIndex == activeIndex
    local temp = {
      activeSlot = 1,
      slots = { [1] = slot },
      hunger = clampMeter(slot.hunger == nil and 4 or slot.hunger),
      fun = clampMeter(slot.fun == nil and 4 or slot.fun),
      clean = clampMeter(slot.clean == nil and 4 or slot.clean),
      careRemainder = slot.careRemainder or { hunger = 0, fun = 0, clean = 0 },
      careLastRealAt = tonumber(slot.careLastRealAt) or now,
      wastePresent = slot.wastePresent == true,
      wasteCount = math.max(0, math.min(WASTE_MAX,
        math.floor(tonumber(slot.wasteCount) or (slot.wastePresent and 1 or 0)))),
      wasteExposure = math.max(0, tonumber(slot.wasteExposure) or 0),
      wastePenalty = math.max(0, tonumber(slot.wastePenalty) or 0),
      digestion = math.max(0, tonumber(slot.digestion) or 0),
      poopDueAt = tonumber(slot.poopDueAt),
      poopPendingWake = slot.poopPendingWake == true,
      devPoopQueued = slot.devPoopQueued == true,
      dietStrain = math.max(0, tonumber(slot.dietStrain) or 0),
      sicknessRisk = slot.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 },
      sickness = slot.sickness,
      sleepGoodSeconds = math.max(0, tonumber(slot.sleepGoodSeconds) or 0),
      sleepWasWindow = slot.sleepWasWindow == true,
      lightsOn = s.lightsOn ~= false,
      carePaused = s.carePaused == true,
      zeldaCareTipsSeen = isActive and (s.zeldaCareTipsSeen or {}) or {},
      zeldaPendingTip = isActive and s.zeldaPendingTip or nil,
      friendshipMasteredSpecies = s.friendshipMasteredSpecies or {},
      friendshipMilestones = s.friendshipMilestones or {},
      unlockedNeoBabies = s.unlockedNeoBabies or {},
      unlockedEggs = s.unlockedEggs or {},
    }

    local elapsed, crossed = advanceCareClock(temp, now, deferPoopAnimation == true, game)

    slot.hunger = clampMeter(temp.hunger)
    slot.fun = clampMeter(temp.fun)
    slot.clean = clampMeter(temp.clean)
    slot.careRemainder = temp.careRemainder
    slot.careLastRealAt = tonumber(temp.careLastRealAt) or now
    slot.wastePresent = temp.wastePresent == true
    slot.wasteCount = math.max(0, math.min(WASTE_MAX, math.floor(tonumber(temp.wasteCount) or 0)))
    slot.wasteExposure = math.max(0, tonumber(temp.wasteExposure) or 0)
    slot.wastePenalty = math.max(0, tonumber(temp.wastePenalty) or 0)
    slot.digestion = math.max(0, tonumber(temp.digestion) or 0)
    slot.poopDueAt = tonumber(temp.poopDueAt)
    slot.poopPendingWake = temp.poopPendingWake == true
    slot.devPoopQueued = temp.devPoopQueued == true
    slot.dietStrain = math.max(0, tonumber(temp.dietStrain) or 0)
    slot.sicknessRisk = temp.sicknessRisk
    slot.sickness = temp.sickness
    slot.sleepGoodSeconds = math.max(0, tonumber(temp.sleepGoodSeconds) or 0)
    slot.sleepWasWindow = temp.sleepWasWindow == true
    normalizeWellnessState(slot)

    -- Progression tables are shared by reference. Only scalar Zelda state needs
    -- to be copied back. Routine warnings from inactive residents wait until
    -- that resident is selected; a 100-Friendship milestone is global enough
    -- to surface immediately.
    s.friendshipMasteredSpecies = temp.friendshipMasteredSpecies
    s.friendshipMilestones = temp.friendshipMilestones
    s.unlockedNeoBabies = temp.unlockedNeoBabies
    s.unlockedEggs = temp.unlockedEggs
    if isActive then
      s.zeldaCareTipsSeen = temp.zeldaCareTipsSeen
      s.zeldaPendingTip = temp.zeldaPendingTip
      copySlotToTopLevel(s, slotIndex)
    elseif temp.zeldaPendingTip == "friendship" then
      s.zeldaPendingTip = "friendship"
    end
    return elapsed, crossed
  end

  local function advanceAllResidentCare(s, suppliedNow, game, deferActivePoop)
    if type(s) ~= "table" or type(s.slots) ~= "table" then return 0, false end
    local now = tonumber(suppliedNow) or wallNow()
    local activeIndex = math.max(1, math.min(SLOT_COUNT, math.floor(tonumber(s.activeSlot) or 1)))
    local activeElapsed, crossed = 0, false
    for i = 1, SLOT_COUNT do
      local slot = s.slots[i]
      if slot and slot.kind == "baby" then
        local elapsed, hit = advanceResidentCareSlot(s, i, now,
          deferActivePoop == true and i == activeIndex, game)
        if i == activeIndex then activeElapsed = elapsed end
        crossed = crossed or hit
      end
    end
    local active = s.slots[activeIndex]
    if not (active and active.kind == "baby") then
      s.careLastRealAt = now
    end
    return activeElapsed, crossed
  end

  local function scheduleNextRoom(s, now)
    s.roomCycle = (tonumber(s.roomCycle) or 0) + 1
    local extraMinutes = (math.floor(now / 60) + s.roomCycle * 37) % 61
    s.nextRoomAt = now + (60 + extraMinutes) * 60
  end

  local function updateRoomRotation(s)
    local now = os.time()
    if not s.nextRoomAt then
      scheduleNextRoom(s, now)
      return
    end

    local loops = 0
    while now >= s.nextRoomAt and loops < 16 do
      local room = math.floor(tonumber(s.roomIndex) or 1)
      s.roomIndex = (room % 3) + 1
      scheduleNextRoom(s, s.nextRoomAt)
      loops = loops + 1
    end
    if loops >= 16 and now >= s.nextRoomAt then
      s.roomIndex = ((math.floor(now / 3600)) % 3) + 1
      scheduleNextRoom(s, now)
    end
  end

  local function nowSeconds()
    return (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  end

  local function randomBabyWalkIndex()
    local pick
    if love.math and love.math.random then
      pick = love.math.random(#BABY_RANDOM_STARTS)
    else
      pick = math.random(#BABY_RANDOM_STARTS)
    end
    return BABY_RANDOM_STARTS[pick]
  end

  local function persistedBabyWalkIndex(s)
    local idx = math.floor(tonumber(s and s.pausedBabyWalkIndex) or 0)
    if idx >= 1 and idx <= #BABY_WALK then return idx end
    return nil
  end

  local function drawImage(image, x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x or 0, y or 0)
  end

  local function drawEgg(art, game, x, y, scale, neoSpecies)
    scale = scale or 1
    local large = art and art.eggLarge
    local egg = large or (art and art.egg)
    if not (egg and egg.image) then
      Font.draw("EGG", x or 0, y or 0)
      return
    end
    local G = love.graphics
    local function body()
      G.setColor(1, 1, 1, 1)
      local renderScale = scale * (large and 1 or 2)
      if egg.quad then
        G.draw(egg.image, egg.quad, x or 0, y or 0, 0, renderScale, renderScale)
      else
        G.draw(egg.image, x or 0, y or 0, 0, renderScale, renderScale)
      end
    end
    local palettes = game and game.data and game.data.gen2Palettes
    local colors = (neoSpecies and NEO.eggPalettes[neoSpecies])
      or (palettes and Palettes.monColors(palettes, "EGG", false) or nil)
    if colors and GbcPalette.available() then GbcPalette.with(colors, body) else body() end
    G.setColor(1, 1, 1, 1)
  end

  local function eggRenderDimensions(art, scale)
    scale = scale or 1
    local large = art and art.eggLarge
    local egg = large or (art and art.egg)
    if not egg then return 0, 0 end
    local renderScale = scale * ((large and 1) or 2)
    return math.floor((egg.width or 0) * renderScale), math.floor((egg.height or 0) * renderScale)
  end

  local function eggTopLeftForCenter(art, centerX, baselineY, scale)
    local w, h = eggRenderDimensions(art, scale)
    return math.floor((centerX or 0) - w / 2 + 0.5), math.floor((baselineY or 0) - h)
  end

  local function eggElapsedMinutes(slot, game)
    if type(slot) ~= "table" or slot.kind ~= "egg" then return 0 end
    local gameNow = gameMinuteStamp(game)
    local startedGame = tonumber(slot.startedMinute) or gameNow
    local gameElapsed = math.max(0, gameNow - startedGame)

    -- Nursery screens can pause PokeSurvive's synthetic clock. Keep a real
    -- timestamp from the same egg-claim moment and use whichever elapsed
    -- clock is farther ahead. This lets an egg visibly progress while the
    -- Nursery is open, while still honoring accelerated in-game time jumps
    -- such as PokeSurvive camping once the player returns. Using max() avoids
    -- double-counting the normal 1:1 passage of time.
    local startedReal = tonumber(slot.startedRealAt)
    if not startedReal then
      startedReal = wallNow() - gameElapsed * 60
      slot.startedRealAt = startedReal
    end
    local realElapsed = math.max(0, wallNow() - startedReal) / 60
    return math.max(gameElapsed, realElapsed)
  end

  local function eggWiggleFrame(slot, game, paused)
    if paused or type(slot) ~= "table" or slot.kind ~= "egg" then return 0 end
    local elapsed = eggElapsedMinutes(slot, game)
    if elapsed < EGG_WIGGLE_START_MINUTES then return 0 end

    -- Minute 7 uses the slowest burst, minute 8 is quicker, and minute 9+
    -- uses the strongest cadence. For this prototype the egg deliberately
    -- remains unhatched after minute ten so the vanilla wiggle can be tested
    -- indefinitely while the full hatch roster is being built.
    local stage = math.max(1, math.min(3, math.floor(elapsed) - EGG_WIGGLE_START_MINUTES + 1))
    local activeSeconds = #EGG_WIGGLE_SEQUENCE * EGG_VANILLA_FRAME_SECONDS
    local period = activeSeconds + (EGG_WIGGLE_REST[stage] or 0.70)
    local t = nowSeconds() % period
    if t >= activeSeconds then return 0 end
    local index = math.floor(t / EGG_VANILLA_FRAME_SECONDS) + 1
    return EGG_WIGGLE_SEQUENCE[index] or 0
  end

  local function drawEggWiggleFrame(art, game, frame, x, y, neoSpecies)
    if not frame or frame <= 0 then
      drawEgg(art, game, x, y, 1, neoSpecies)
      return
    end
    local image = art and art.eggWiggle and art.eggWiggle[frame]
    if not image then
      drawEgg(art, game, x, y, 1, neoSpecies)
      return
    end
    local G = love.graphics
    local function body()
      G.setColor(1, 1, 1, 1)
      G.draw(image, x or 0, y or 0)
    end
    local palettes = game and game.data and game.data.gen2Palettes
    local colors = (neoSpecies and NEO.eggPalettes[neoSpecies])
      or (palettes and Palettes.monColors(palettes, "EGG", false) or nil)
    if colors and GbcPalette.available() then GbcPalette.with(colors, body) else body() end
    G.setColor(1, 1, 1, 1)
  end

  function NEO.officialMaskKeeps(mask, x, y)
    if not (mask and mask.rows and x >= 0 and y >= 0 and x < mask.w and y < mask.h) then return false end
    local row = mask.rows[y + 1]
    if type(row) ~= "string" then return false end
    local nibbleIndex = math.floor(x / 4) + 1
    local nibble = tonumber(row:sub(nibbleIndex, nibbleIndex), 16) or 0
    local shift = 3 - (x % 4)
    return math.floor(nibble / (2 ^ shift)) % 2 == 1
  end

  function NEO.officialMaskedImage(path, mask, cropX, cropY)
    if not (path and mask and love.image and love.image.newImageData
       and love.graphics and love.graphics.newImage) then return nil end
    local okSource, source = pcall(Assets.imageData, path)
    if not (okSource and source) then return nil end

    local w, h = math.floor(tonumber(mask.w) or 0), math.floor(tonumber(mask.h) or 0)
    if w <= 0 or h <= 0 then return nil end
    local sw, sh = source:getWidth(), source:getHeight()
    local sx = cropX
    local sy = cropY
    if sx == nil then sx = math.max(0, math.floor((sw - w) / 2)) end
    if sy == nil then sy = math.max(0, math.floor((sh - h) / 2)) end
    sx, sy = math.floor(tonumber(sx) or 0), math.floor(tonumber(sy) or 0)
    if sx < 0 or sy < 0 or sx + w > sw or sy + h > sh then return nil end

    local okData, outData = pcall(love.image.newImageData, w, h)
    if not (okData and outData) then return nil end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b = source:getPixel(sx + x, sy + y)
        outData:setPixel(x, y, r, g, b, NEO.officialMaskKeeps(mask, x, y) and 1 or 0)
      end
    end
    local okImage, image = pcall(love.graphics.newImage, outData)
    if okImage and image then
      image:setFilter("nearest", "nearest")
      return image
    end
    return nil
  end

  local function monAnimNurseryAltFrame(anim)
    if not (anim and anim.frames) then return 1 end
    -- Use the second pose frame from Crystal's extracted animation sheet for
    -- the Nursery's alternate pose. If a species exposes fewer than two
    -- frames, gracefully fall back to the last available animated frame.
    if #anim.frames >= 2 then return 2 end
    if #anim.frames >= 1 then return 1 end
    return 1
  end

  local function drawBabyStep(art, step, slot, game)
    local species = slot and slot.species
    local mon = slot and slot.nurseryMon
    local randomizedTypes = NEO.psRandomTypesEnabled(game) and mon and mon.types or nil
    local cinnabarColors = NEO.cinnabarPalette(game and game.data, mon)
    local wantsRetail = slot and slot.spriteStyle == "crystal" and OFFICIAL_BABY_SPECIES[species] == true
    local speciesArt = wantsRetail and art.retailBabySpecies and art.retailBabySpecies[species]
      or (art.babySpecies and species and art.babySpecies[species])
    local isShiny = mon and mon.shiny == true

    -- NEO presentation sprites are authored true-colour, so when an external
    -- per-Pokemon palette is active use the palette-ready grayscale companion
    -- art. Retail CRYSTAL sprites are already grayscale and need no swap.
    local usePaletteCustom = (cinnabarColors or (randomizedTypes and not isShiny))
      and speciesArt and speciesArt.randomFrames and not wantsRetail
    local frames = speciesArt and (usePaletteCustom and speciesArt.randomFrames
      or ((isShiny and speciesArt.shinyFrames) or speciesArt.frames))
    local backArt = speciesArt and (usePaletteCustom and speciesArt.randomBack
      or ((isShiny and speciesArt.shinyBack) or speciesArt.back))
    local speciesFrame = frames and frames[step.frame]
    if wantsRetail and step.actionFrame and speciesArt and speciesArt.actionFrames then
      speciesFrame = speciesArt.actionFrames[step.actionFrame] or speciesFrame
    end
    local useBack = step.back == true and backArt and backArt.image
    local image = useBack and backArt.image
      or (speciesFrame and speciesFrame.image)
      or (speciesArt and speciesArt.image)
      or art.baby[step.frame]
    if not image then return end
    local quad = useBack and backArt.quad or (speciesFrame and speciesFrame.quad or nil)
    local w = useBack and (backArt.width or image:getWidth())
      or (speciesFrame and speciesFrame.width or image:getWidth())
    local h = useBack and (backArt.height or image:getHeight())
      or (speciesFrame and speciesFrame.height or image:getHeight())
    local frameOffsetX = tonumber(speciesFrame and speciesFrame.offsetX) or 0
    local frameOffsetY = tonumber(speciesFrame and speciesFrame.offsetY) or 0
    local x = step.x + math.floor((56 - w) / 2) + frameOffsetX
    local y = step.y + (56 - h) + frameOffsetY
    local G = love.graphics
    local rotation = math.rad(tonumber(step.rotation) or 0)
    local function body()
      G.setColor(1, 1, 1, 1)
      if rotation ~= 0 then
        -- Rotate around the sprite centre so 90-degree cartwheel steps do not
        -- orbit around the top-left corner. Mirroring still works for babies
        -- facing the opposite travel direction.
        local sx = step.flip and -1 or 1
        if quad then
          G.draw(image, quad, x + w / 2, y + h / 2, rotation, sx, 1, w / 2, h / 2)
        else
          G.draw(image, x + w / 2, y + h / 2, rotation, sx, 1, w / 2, h / 2)
        end
      elseif step.flip then
        if quad then G.draw(image, quad, x + w, y, 0, -1, 1) else G.draw(image, x + w, y, 0, -1, 1) end
      else
        if quad then G.draw(image, quad, x, y) else G.draw(image, x, y) end
      end
    end
    if cinnabarColors and speciesArt then
      -- Mutant Monster Lab color mutations are individual-Pokemon state and
      -- intentionally override shiny / PokeSurvive palette presentation, just
      -- as MML does in battle and Summary.
      if GbcPalette.available() then GbcPalette.with(cinnabarColors, body) else body() end
    elseif randomizedTypes and not isShiny and speciesArt then
      -- Use PokeSurvive's own palette algorithm when its compatibility bridge
      -- is present. CRYSTAL and NEO therefore show the exact same seeded color
      -- pair, and a reload cannot invent a second Nursery-only palette.
      local colors = NEO.psPaletteForTypes(game,species,randomizedTypes)
      if colors and GbcPalette.available() then GbcPalette.with(colors, body) else body() end
    elseif speciesArt and not speciesArt.trueColor then
      local palettes = game and game.data and game.data.gen2Palettes
      local colors = palettes and Palettes.monColors(palettes, species, isShiny) or nil
      if colors and GbcPalette.available() then GbcPalette.with(colors, body) else body() end
    else
      body()
    end
    G.setColor(1, 1, 1, 1)
    local visible = useBack and backArt.visible or (speciesFrame and speciesFrame.visible or nil)
    if visible then
      local vx = x + (visible.left or 0)
      local vy = y + (visible.top or 0)
      local vw = math.max(1, (visible.right or w) - (visible.left or 0))
      local vh = math.max(1, (visible.bottom or h) - (visible.top or 0))
      -- For mirrored sprites the visible horizontal inset mirrors too. Thought
      -- bubbles only need the visual centre/top; preserve that centre exactly.
      if step.flip then vx = x + w - (visible.right or w) end
      return { x = vx, y = vy, w = vw, h = vh }
    end
    return { x = x, y = y, w = w, h = h }
  end

  local function loadAssets(game)
    local out = {
      rooms = {
        mod.assets:image("assets/room_blue.png"),
        mod.assets:image("assets/room_green.png"),
        mod.assets:image("assets/room_pink.png"),
      },
      roomsLightsOff = {
        mod.assets:image("assets/room_blue_lightsoff.png"),
        mod.assets:image("assets/room_green_lightsoff.png"),
        mod.assets:image("assets/room_pink_lightsoff.png"),
      },
      baby = {
        mod.assets:image("assets/baby_idle_1.png"),
        mod.assets:image("assets/baby_idle_2.png"),
      },
      berry = {
        mod.assets:image("assets/berry_full.png"),
        mod.assets:image("assets/berry_partly.png"),
        mod.assets:image("assets/berry_mostly.png"),
      },
      food = {
        fresh_water = {
          mod.assets:image("assets/food_fresh_water_full.png"),
          mod.assets:image("assets/food_fresh_water_half.png"),
          mod.assets:image("assets/food_fresh_water_mostly.png"),
        },
        soda_pop = {
          mod.assets:image("assets/food_soda_pop_full.png"),
          mod.assets:image("assets/food_soda_pop_half.png"),
          mod.assets:image("assets/food_soda_pop_mostly.png"),
        },
        lemonade = {
          mod.assets:image("assets/food_lemonade_full.png"),
          mod.assets:image("assets/food_lemonade_half.png"),
          mod.assets:image("assets/food_lemonade_mostly.png"),
        },
        moomoo_milk = {
          mod.assets:image("assets/food_moomoo_milk_full.png"),
          mod.assets:image("assets/food_moomoo_milk_half.png"),
          mod.assets:image("assets/food_moomoo_milk_mostly.png"),
        },
        ragecandybar = {
          mod.assets:image("assets/food_ragecandybar_full.png"),
          mod.assets:image("assets/food_ragecandybar_half.png"),
          mod.assets:image("assets/food_ragecandybar_mostly.png"),
        },
        berry_juice = {
          mod.assets:image("assets/food_berry_juice_full.png"),
          mod.assets:image("assets/food_berry_juice_half.png"),
          mod.assets:image("assets/food_berry_juice_mostly.png"),
        },
      },
      alert = mod.assets:image("assets/care_alert.png"),
      zelda = mod.assets:image("assets/zelda_portrait.png"),
      zeldaTrainer = nil,
      heart = mod.assets:image("assets/meter_heart.png"),
      halfHeart = mod.assets:image("assets/meter_half_heart.png"),
      selector = mod.assets:image("assets/icon_selector.png"),
      waste = {
        mod.assets:image("assets/waste_1.png"),
        mod.assets:image("assets/waste_2.png"),
      },
      flush = mod.assets:image("assets/flush.png"),
      sleepBassinet = mod.assets:image("assets/sleep_bassinet.png"),
      play = {
        ball = mod.assets:image("assets/play_ball.png"),
        flagDown = mod.assets:image("assets/play_flag_down.png"),
        flagUp = mod.assets:image("assets/play_flag_up.png"),
        arrows = {
          left = mod.assets:image("assets/play_arrow_left.png"),
          up = mod.assets:image("assets/play_arrow_up.png"),
          right = mod.assets:image("assets/play_arrow_right.png"),
          down = mod.assets:image("assets/play_arrow_down.png"),
        },
      },
      medicine = {
        antidote = mod.assets:image("assets/medicine_antidote.png"),
        awakening = mod.assets:image("assets/medicine_awakening.png"),
        burn_heal = mod.assets:image("assets/medicine_burn_heal.png"),
        ice_heal = mod.assets:image("assets/medicine_ice_heal.png"),
        parlyz_heal = mod.assets:image("assets/medicine_parlyz_heal.png"),
        full_heal = mod.assets:image("assets/medicine_full_heal.png"),
      },
      thought = {
        happy = mod.assets:image("assets/thought_happy.png"),
        angry = mod.assets:image("assets/thought_angry.png"),
        ecstatic = mod.assets:image("assets/thought_ecstatic.png"),
        no = mod.assets:image("assets/thought_no.png"),
        sick = mod.assets:image("assets/thought_sick.png"),
        famished = mod.assets:image("assets/thought_famished.png"),
        sad = mod.assets:image("assets/thought_sad.png"),
        miserable = mod.assets:image("assets/thought_miserable.png"),
        exhausted = mod.assets:image("assets/thought_exhausted.png"),
        exclamation = mod.assets:image("assets/thought_exclamation.png"),
        relaxed = mod.assets:image("assets/thought_relaxed.png"),
        curious = mod.assets:image("assets/thought_curious.png"),
        worried = mod.assets:image("assets/thought_worried.png"),
      },
      egg = nil,
      eggLarge = nil,
      eggWiggle = {
        mod.assets:image("assets/egg_wiggle_1.png"),
        mod.assets:image("assets/egg_wiggle_2.png"),
      },
      babySpecies = {},
      retailBabySpecies = {},
    }

    -- The supplied Tamagotchi/feedback sprites are deliberately tiny pixel art;
    -- lock every one to nearest-neighbour filtering so scaling never softens it.
    for _, image in pairs({ out.play.ball, out.play.flagDown, out.play.flagUp }) do
      if image and image.setFilter then image:setFilter("nearest", "nearest") end
    end
    for _, image in pairs(out.play.arrows or {}) do
      if image and image.setFilter then image:setFilter("nearest", "nearest") end
    end
    for _, image in pairs(out.medicine or {}) do
      if image and image.setFilter then image:setFilter("nearest", "nearest") end
    end
    for _, image in pairs(out.thought or {}) do
      if image and image.setFilter then image:setFilter("nearest", "nearest") end
    end
    if out.sleepBassinet and out.sleepBassinet.setFilter then out.sleepBassinet:setFilter("nearest", "nearest") end

    -- Neo Nursery ships two front poses, a back pose, and matching shiny art
    -- for all nineteen babies. These are Nursery presentation sprites only for
    -- the eight official babies; their normal Crystal battle art remains intact.
    -- The eleven cut babies also use their supplied front/back art as their real
    -- registered species battle sprites because Crystal has no native records.
    for species, stem in pairs(NEO.artStems) do
      local f1Rel = "assets/neo_" .. stem .. "_front1.png"
      local f2Rel = "assets/neo_" .. stem .. "_front2.png"
      local backRel = "assets/neo_" .. stem .. "_back.png"
      local sf1Rel = "assets/neo_" .. stem .. "_shiny_front1.png"
      local sf2Rel = "assets/neo_" .. stem .. "_shiny_front2.png"
      local sbackRel = "assets/neo_" .. stem .. "_shiny_back.png"
      local rf1Rel = "assets/neo_" .. stem .. "_rand_front1.png"
      local rf2Rel = "assets/neo_" .. stem .. "_rand_front2.png"
      local rbackRel = "assets/neo_" .. stem .. "_rand_back.png"
      local f1 = mod.assets:image(f1Rel)
      local f2 = mod.assets:image(f2Rel)
      local back = mod.assets:image(backRel)
      local sf1 = mod.assets:image(sf1Rel)
      local sf2 = mod.assets:image(sf2Rel)
      local sback = mod.assets:image(sbackRel)
      local rf1 = mod.assets:image(rf1Rel)
      local rf2 = mod.assets:image(rf2Rel)
      local rback = mod.assets:image(rbackRel)
      for _, image in ipairs({ f1, f2, back, sf1, sf2, sback, rf1, rf2, rback }) do
        if image and image.setFilter then image:setFilter("nearest", "nearest") end
      end
      if f1 then
        local entry = {
          image = f1,
          trueColor = true,
          frames = {
            { image = f1, width = f1:getWidth(), height = f1:getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front1 or nil },
            { image = f2 or f1, width = (f2 or f1):getWidth(), height = (f2 or f1):getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front2 or nil },
          },
          back = back and { image = back, width = back:getWidth(), height = back:getHeight(),
            visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].back or nil } or nil,
          shinyFrames = {
            { image = sf1 or f1, width = (sf1 or f1):getWidth(), height = (sf1 or f1):getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front1 or nil },
            { image = sf2 or sf1 or f2 or f1, width = (sf2 or sf1 or f2 or f1):getWidth(), height = (sf2 or sf1 or f2 or f1):getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front2 or nil },
          },
          shinyBack = (sback or back) and {
            image = sback or back,
            width = (sback or back):getWidth(), height = (sback or back):getHeight(),
            visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].back or nil,
          } or nil,
          randomFrames = rf1 and {
            { image = rf1, width = rf1:getWidth(), height = rf1:getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front1 or nil },
            { image = rf2 or rf1, width = (rf2 or rf1):getWidth(), height = (rf2 or rf1):getHeight(),
              visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].front2 or nil },
          } or nil,
          randomBack = rback and { image = rback, width = rback:getWidth(), height = rback:getHeight(),
            visible = NEO.spriteBounds[species] and NEO.spriteBounds[species].back or nil } or nil,
        }
        -- Cut babies have no Crystal animation sheet. Their quiet first pose is
        -- the sleep fallback until/unless dedicated sleep art is authored.
        entry.sleep = { image = f1, width = f1:getWidth(), height = f1:getHeight(), trueColor = true }
        entry.shinySleep = sf1 and {
          image = sf1, width = sf1:getWidth(), height = sf1:getHeight(), trueColor = true,
        } or entry.sleep
        out.babySpecies[species] = entry
      end
    end

    -- Cache the released Crystal art for the eight official babies by applying
    -- the user-authored silhouette masks to the player's own imported assets at
    -- runtime. No vanilla Pokemon sprite PNGs are shipped by Neo Nursery.
    for _, species in ipairs(OFFICIAL_BABY_POOL) do
      local def = game and game.data and game.data.pokemon and game.data.pokemon[species]
      local masks = NEO.officialCrystalMasks[species]
      if def and def.spriteFront and masks then
        local front = NEO.officialMaskedImage(def.spriteFront, masks.front1)
        local back = def.spriteBack and NEO.officialMaskedImage(def.spriteBack, masks.back) or nil
        local alt = nil
        local actionFrames = {}
        local anim = def.anim
        if anim and anim.sheet and anim.tiles and masks.front2 then
          local size = math.max(8, math.floor(tonumber(anim.tiles) or 7) * 8)
          local frameIndex = math.max(1, math.floor(tonumber(monAnimNurseryAltFrame(anim)) or 1))
          if masks.front2.w == size and masks.front2.h == size then
            alt = NEO.officialMaskedImage(anim.sheet, masks.front2, 0, frameIndex * size)
          end

          -- Pull a small curated set of extra Crystal animation frames from
          -- the user's imported ROM cache. Only compact keep/remove masks ship
          -- with Neo Nursery, so no official Pokemon sprite PNGs are bundled.
          local actionMasks = NEO.officialCrystalActionMasks[species] or {}
          for actionIndex, actionMask in pairs(actionMasks) do
            if actionMask.w == size and actionMask.h == size then
              local image = NEO.officialMaskedImage(
                anim.sheet, actionMask, 0, math.floor(tonumber(actionIndex) or 0) * size)
              if image then
                actionFrames[actionIndex] = {
                  image = image,
                  width = image:getWidth(),
                  height = image:getHeight(),
                  visible = NEO.officialMaskBounds(actionMask),
                }
              end
            end
          end
        end
        if front then
          out.retailBabySpecies[species] = {
            image = front, trueColor = false,
            frames = {
              { image = front, width = front:getWidth(), height = front:getHeight() },
              alt and { image = alt, width = alt:getWidth(), height = alt:getHeight() }
                or { image = front, width = front:getWidth(), height = front:getHeight() },
            },
            actionFrames = actionFrames,
            back = back and { image = back, width = back:getWidth(), height = back:getHeight() } or nil,
          }
        end
      end
    end

    -- The supplied Spaceworld/cut-style art for the eight official babies is
    -- treated as one coherent Nursery presentation set. Do NOT replace its
    -- sleep pose with a frame from the retail Crystal animation sheet: that
    -- visibly changes the baby into a different design at bedtime. front1
    -- (and shiny front1) remains the calm sleep fallback unless dedicated
    -- matching sleep art is added later.

    -- Zelda's tutorial visit uses Crystal's actual POKEFAN F battle frontpic
    -- from the player's imported ROM cache. No trainer art is shipped by the
    -- mod; an older cache simply falls back to the small authored Zelda icon.
    local battleHud = game and game.data and game.data.gen2MenuGfx
      and game.data.gen2MenuGfx.battleHud
    local trainerPics = battleHud and battleHud.trainerPics
    local zeldaTrainerPath = trainerPics and trainerPics.POKEFANF
    if zeldaTrainerPath then
      -- A battle frontpic has an opaque white background, but white is also a
      -- legitimate colour INSIDE the Pokefan F art (especially her dolls).
      -- The previous keyed shader erased every shade-0 pixel and punched holes
      -- through those details. Build a runtime-only alpha mask from the
      -- player's own imported ROM art instead: flood-fill only shade-0 pixels
      -- connected to the OUTER edge, leaving enclosed white sprite pixels
      -- fully opaque. No ROM-derived trainer art is shipped with this mod.
      local madeCutout = false
      if love.image and love.image.newImageData and love.graphics and love.graphics.newImage then
        local okData, imageData = pcall(love.image.newImageData, zeldaTrainerPath)
        if okData and imageData then
          local w, h = imageData:getWidth(), imageData:getHeight()
          local queueX, queueY, head, tail = {}, {}, 1, 0
          local seen = {}
          local function key(x, y) return y * w + x + 1 end
          local function isWhite(x, y)
            local r, g, b, a = imageData:getPixel(x, y)
            return (a or 1) > 0 and r > 0.95 and g > 0.95 and b > 0.95
          end
          local function enqueue(x, y)
            if x < 0 or y < 0 or x >= w or y >= h then return end
            local k = key(x, y)
            if seen[k] or not isWhite(x, y) then return end
            seen[k] = true
            tail = tail + 1
            queueX[tail], queueY[tail] = x, y
          end
          for x = 0, w - 1 do enqueue(x, 0); enqueue(x, h - 1) end
          for y = 0, h - 1 do enqueue(0, y); enqueue(w - 1, y) end
          while head <= tail do
            local x, y = queueX[head], queueY[head]
            head = head + 1
            local r, g, b = imageData:getPixel(x, y)
            imageData:setPixel(x, y, r, g, b, 0)
            enqueue(x - 1, y); enqueue(x + 1, y)
            enqueue(x, y - 1); enqueue(x, y + 1)
          end
          local okImage, image = pcall(love.graphics.newImage, imageData)
          if okImage and image then
            out.zeldaTrainer = image
            madeCutout = true
          end
        end
      end
      if not madeCutout then
        local ok, image = pcall(Assets.image, zeldaTrainerPath)
        if ok and image then out.zeldaTrainer = image end
      end
    end

    -- Prefer Crystal's actual 5x5 EggPic used by the vanilla Pokémon status
    -- page.  This is the larger resting egg the Nursery mockups reference,
    -- and is also the same picture the hatch scene begins from.
    local menuGfx = game and game.data and game.data.gen2MenuGfx
    local eggPicPath = menuGfx and menuGfx.eggHatch and menuGfx.eggHatch.egg
    if eggPicPath then
      local ok, image = pcall(Assets.image, eggPicPath)
      if ok and image then out.eggLarge = { image = image, width = image:getWidth(), height = image:getHeight() } end
    end

    -- Keep Crystal's party EGG icon as a compatibility fallback for caches
    -- that predate extraction of EggPic.
    -- The first 16x16 frame is the resting egg shown by the vanilla party UI.
    local icons = game and game.data and game.data.gen2Icons
    local eggEntry = icons and icons.icons and icons.icons.ICON_EGG
    if eggEntry and eggEntry.image then
      local ok, image = pcall(Assets.image, eggEntry.image)
      if ok and image then
        local w = eggEntry.width or 16
        local h = math.min(eggEntry.height or 16, image:getHeight())
        if (eggEntry.frames or 1) > 1 then h = math.floor(h / eggEntry.frames) end
        local qok, quad = pcall(love.graphics.newQuad, 0, 0, w, h,
          image:getWidth(), image:getHeight())
        if qok then out.egg = { image = image, quad = quad, width = w, height = h } end
      end
    end

    for _, room in ipairs(out.rooms) do room:setFilter("nearest", "nearest") end
    for _, room in ipairs(out.roomsLightsOff) do room:setFilter("nearest", "nearest") end
    for _, baby in ipairs(out.baby) do baby:setFilter("nearest", "nearest") end
    for _, berry in ipairs(out.berry) do berry:setFilter("nearest", "nearest") end
    for _, stages in pairs(out.food or {}) do
      for _, image in ipairs(stages) do image:setFilter("nearest", "nearest") end
    end
    out.alert:setFilter("nearest", "nearest")
    out.zelda:setFilter("nearest", "nearest")
    if out.zeldaTrainer then out.zeldaTrainer:setFilter("nearest", "nearest") end
    out.heart:setFilter("nearest", "nearest")
    out.halfHeart:setFilter("nearest", "nearest")
    out.selector:setFilter("nearest", "nearest")
    for _, waste in ipairs(out.waste) do waste:setFilter("nearest", "nearest") end
    out.flush:setFilter("nearest", "nearest")
    if out.egg and out.egg.image then out.egg.image:setFilter("nearest", "nearest") end
    if out.eggLarge and out.eggLarge.image then out.eggLarge.image:setFilter("nearest", "nearest") end
    for _, eggFrame in ipairs(out.eggWiggle) do eggFrame:setFilter("nearest", "nearest") end
    return out
  end

  local function drawMeter(art, kind, value)
    value = clampMeter(value)
    local xs = HEART_X[kind]
    local full = math.floor(value)
    for i = 1, full do
      drawImage(art.heart, xs[i], HEART_Y)
    end
    if value - full >= 0.5 and full < 4 then
      drawImage(art.halfHeart, xs[full + 1], HEART_Y)
    end
  end

  local function ownedFoods(game)
    local inv = game and game.save and game.save.inventory or {}
    local rows = {}
    for _, def in ipairs(FOOD_DEFS) do
      local count = math.floor(tonumber(inv[def.id]) or 0)
      if count > 0 then
        rows[#rows + 1] = {
          id = def.id,
          label = def.label,
          hunger = def.hunger,
          anim = def.anim,
          count = count,
        }
      end
    end
    return rows
  end


  local function ownedMedicines(game)
    local inv = game and game.save and game.save.inventory or {}
    local rows = {}
    for _, def in ipairs(MEDICINE_DEFS) do
      local count = math.floor(tonumber(inv[def.id]) or 0)
      if count > 0 then
        rows[#rows + 1] = {
          id = def.id,
          label = def.label,
          count = count,
          cures = def.cures,
          asset = def.asset,
        }
      end
    end
    return rows
  end

  local function drawMenuCursor(x, y)
    -- Go through the same Chrome cursor helper used by Crystal's own menus.
    -- The food rows are tile-aligned, so this draws charmap $ED verbatim.
    Chrome.cursor(math.floor(x / 8), math.floor(y / 8))
  end

  local function drawNativeMenuArrow(x, y, faceLeft)
    -- Use Crystal's actual filled menu-cursor tile ($ED).  The cartridge only
    -- stores the right-facing version, so the left selector is that SAME
    -- native glyph mirrored horizontally rather than a Unicode/custom arrow.
    local G = love.graphics
    G.setColor(0, 0, 0, 1)
    if faceLeft then
      G.push()
      G.translate((x or 0) + 8, y or 0)
      G.scale(-1, 1)
      Font.drawCode(Chrome.CURSOR, 0, 0)
      G.pop()
    else
      Font.drawCode(Chrome.CURSOR, x or 0, y or 0)
    end
    G.setColor(0, 0, 0, 1)
  end

  local function drawNativeScrollUp()
    -- Crystal's SCROLLINGMENU up-arrow glyph, not a polygon approximation.
    Chrome.print("▲", 18, 5)
  end

  local function drawNativeScrollDown()
    -- Crystal's native text/scroll down-arrow glyph (charmap $EE).
    Chrome.print("▼", 18, 12)
  end


  local function drawStatusPageNavHint(x, y)
    x = math.floor(x or 109)
    y = math.floor(y or 88)
    drawNativeMenuArrow(x, y, true)
    Font.draw("L/R", x + 11, y)
    drawNativeMenuArrow(x + 37, y, false)
  end

  -- Keep the large Nursery screen closure below LuaJIT's 60-upvalue hard
  -- limit. v0.0.30 crossed that limit when the full Odd Egg hatch path was
  -- added, preventing the entire mod from compiling (and therefore preventing
  -- Zelda and every other hook from initializing). Bundle screen constants
  -- behind one captured table instead of capturing each constant separately.
  local NURSERY_CFG = {
    BABY_STEP_SECONDS = BABY_STEP_SECONDS,
    BABY_WALK = BABY_WALK,
    MOVEMENT_PROFILES = MOVEMENT_PROFILES,
    MOVEMENT_DEFAULT = MOVEMENT_DEFAULT,
    MOVEMENT_TURN_SECONDS = MOVEMENT_TURN_SECONDS,
    MOVEMENT_HOP_SECONDS = MOVEMENT_HOP_SECONDS,
    MOVEMENT_BACK_SECONDS = MOVEMENT_BACK_SECONDS,
    MOVEMENT_CARTWHEEL_SECONDS = MOVEMENT_CARTWHEEL_SECONDS,
    BERRY_EAT = BERRY_EAT,
    CARE_ITEMS = CARE_ITEMS,
    CALL_CONTACTS = CALL_CONTACTS,
    CARE_VISIBLE_ROWS = CARE_VISIBLE_ROWS,
    CLEAN_STEP_SECONDS = CLEAN_STEP_SECONDS,
    EAT_STEP_SECONDS = EAT_STEP_SECONDS,
    EGG_COOLDOWN_SECONDS = EGG_COOLDOWN_SECONDS,
    EGG_HATCH_MINUTES = EGG_HATCH_MINUTES,
    FLUSH_SWEEP = FLUSH_SWEEP,
    FLUSH_Y = FLUSH_Y,
    FOOD_DEFS = FOOD_DEFS,
    FOOD_WEIGHT_TENTHS = FOOD_WEIGHT_TENTHS,
    FULL_HUNGER_REFUSE = FULL_HUNGER_REFUSE,
    GENERIC_EAT = GENERIC_EAT,
    HAPPINESS_STEP_SECONDS = HAPPINESS_STEP_SECONDS,
    REFUSE_STEP_SECONDS = REFUSE_STEP_SECONDS,
    PLAY_MENU_ITEMS = PLAY_MENU_ITEMS,
    THOUGHT_SECONDS = THOUGHT_SECONDS,
    PLAY_RESULT_SECONDS = PLAY_RESULT_SECONDS,
    PLAY_FUN_REWARD = PLAY_FUN_REWARD,
    PLAY_FUN_REWARD_IMPERFECT = PLAY_FUN_REWARD_IMPERFECT,
    PLAY_BABY_LANES = PLAY_BABY_LANES,
    PLAY_BALL_TOP_Y = PLAY_BALL_TOP_Y,
    PLAY_BALL_HIT_MIN_Y = PLAY_BALL_HIT_MIN_Y,
    PLAY_BALL_HIT_MAX_Y = PLAY_BALL_HIT_MAX_Y,
    PLAY_BALL_MISS_Y = PLAY_BALL_MISS_Y,
    PLAY_BALL_FALL_SPEED_START = PLAY_BALL_FALL_SPEED_START,
    PLAY_BALL_FALL_SPEED_END = PLAY_BALL_FALL_SPEED_END,
    PLAY_BALL_RISE_SPEED = PLAY_BALL_RISE_SPEED,
    PLAY_BOUNCE_START_DELAY = PLAY_BOUNCE_START_DELAY,
    PLAY_BOUNCE_BETWEEN_DELAY = PLAY_BOUNCE_BETWEEN_DELAY,
    PLAY_BOUNCE_JUMP_SECONDS = PLAY_BOUNCE_JUMP_SECONDS,
    PLAY_MATCH_RESPONSE_SECONDS = PLAY_MATCH_RESPONSE_SECONDS,
    PLAY_MATCH_RESET_SECONDS = PLAY_MATCH_RESET_SECONDS,
    PLAY_MATCH_WAIT_MIN_SECONDS = PLAY_MATCH_WAIT_MIN_SECONDS,
    PLAY_MATCH_WAIT_RANDOM_SECONDS = PLAY_MATCH_WAIT_RANDOM_SECONDS,
    PLAY_MATCH_TRICK_SECONDS = PLAY_MATCH_TRICK_SECONDS,
    PLAY_MATCH_CHORD_SECONDS = PLAY_MATCH_CHORD_SECONDS,
    PLAY_MEMORY_LENGTHS = PLAY_MEMORY_LENGTHS,
    PLAY_MEMORY_STEP_SECONDS = PLAY_MEMORY_STEP_SECONDS,
    PLAY_MEMORY_LINGER_SECONDS = PLAY_MEMORY_LINGER_SECONDS,
    PLAY_MEMORY_BETWEEN_SECONDS = PLAY_MEMORY_BETWEEN_SECONDS,
    PLAY_MEMORY_FLASH_SECONDS = PLAY_MEMORY_FLASH_SECONDS,
    PLAY_DIRECTIONS = PLAY_DIRECTIONS,
    PERSONALITY_PROFILES = PERSONALITY_PROFILES,
    NEO = NEO,
    CARE_ACTION_FRIENDSHIP = CARE_ACTION_FRIENDSHIP,
    PREFERENCE_FRIENDSHIP_BONUS = PREFERENCE_FRIENDSHIP_BONUS,
    SICKNESS_CURE_FRIENDSHIP = SICKNESS_CURE_FRIENDSHIP,
    DEFAULT_SLEEP_START_HOUR = DEFAULT_SLEEP_START_HOUR,
    DEFAULT_SLEEP_END_HOUR = DEFAULT_SLEEP_END_HOUR,
    SLEEP_FRAME_BY_SPECIES = SLEEP_FRAME_BY_SPECIES,
    SELECTOR_POS = SELECTOR_POS,
    SLOT_COUNT = SLOT_COUNT,
    WASTE_STEP_SECONDS = WASTE_STEP_SECONDS,
    WASTE_POSITIONS = WASTE_POSITIONS,
    WASTE_MAX = WASTE_MAX,
    WASTE_CLEAN_DRAIN_SECONDS = WASTE_CLEAN_DRAIN_SECONDS,
    DIGESTION_FULL_SECONDS = DIGESTION_FULL_SECONDS,
    POOP_DELAY_MIN_SECONDS = POOP_DELAY_MIN_SECONDS,
    POOP_DELAY_MAX_SECONDS = POOP_DELAY_MAX_SECONDS,
    POOP_STEP_SECONDS = POOP_STEP_SECONDS,
    POOP_SHAKE = POOP_SHAKE,
  }

  mod.content.screens:register(SCREEN, {
    new = function(game, opts)
      opts = opts or {}
      local persisted = saveState()
      local persistedSlot = persisted.slots and persisted.slots[persisted.activeSlot or 1]
      local initialCareElapsed = advanceAllResidentCare(persisted, wallNow(), game, false)
      if not (persistedSlot and persistedSlot.kind == "baby") then
        persisted.careLastRealAt = wallNow()
      end
      updateRoomRotation(persisted)

      -- Babycare owns the music while this screen is on the stack.  Crystal's
      -- Game Boy Printer theme is intentionally used instead of the map song.
      local previousMusic = Music.current()
      Music.play(game.data, "Music_Printer", true, { reason = "direct" })

      local state = {
        game = game,
        isOpaque = true,
        babycareNursery = true,
        art = loadAssets(game),
        data = persisted,
        cursor = 1,
        babyWalkIndex = (persisted.carePaused == true and persistedBabyWalkIndex(persisted))
          or ((sleepWindowActiveFor(persisted, game)
            and tonumber(persisted.sleepWalkIndex)) or nil)
          or randomBabyWalkIndex(),
        babyWalkChangedAt = nowSeconds(),
        movementFlourish = nil,
        foodMenu = nil,
        medicineMenu = nil,
        careMenu = nil,
        callMenu = nil,
        playMenu = nil,
        playGame = nil,
        thoughtBubble = nil,
        lastBabyBounds = nil,
        eating = nil,
        medicating = nil,
        refusing = nil,
        cleaning = nil,
        pooping = nil,
        wasteFrame = 1,
        wasteChangedAt = nowSeconds(),
        previousMusic = previousMusic,
        careClockPolledAt = wallNow(),
        pendingHappinessElapsed = initialCareElapsed,
        zeldaDialog = nil,
        zeldaTextBoxOpen = false,
        zeldaTrainerX = 160,
        zeldaTrainerTargetX = 104,
        zeldaSlideMode = nil,
        zeldaSlideChangedAt = nowSeconds(),
        zeldaVisitHold = false,
        zeldaOnboardingLock = persisted.zeldaIntroAwaitingEgg == true
          or persisted.zeldaTutorialFinishing == true,
        zeldaOnboardingReleaseOnExit = false,
        hatchInProgress = false,
      }

      function state:hasAnyNurseryResident()
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          if self.data.slots and self.data.slots[i] then return true end
        end
        return false
      end

      function state:tutorialInputLocked()
        return self.zeldaOnboardingLock == true
          or self.data.zeldaIntroAwaitingEgg == true
          or self.data.zeldaTutorialFinishing == true
      end

      function state:zeldaVisible()
        return self.zeldaDialog ~= nil or self.zeldaVisitHold == true
          or self.zeldaSlideMode ~= nil or (tonumber(self.zeldaTrainerX) or 160) < 160
      end

      function state:presentZeldaText()
        local dialog = self.zeldaDialog
        if not dialog or self.zeldaTextBoxOpen then return end
        self.zeldaTextBoxOpen = true
        local body = zeldaPagesNoScroll(dialog.pages)
        self.game.stack:push(TextBox.new(self.game, body, function()
          self.zeldaTextBoxOpen = false
          local finished = self.zeldaDialog
          self.zeldaDialog = nil
          if finished and type(finished.onDone) == "function" then finished.onDone() end
          if finished and finished.keepAfter then
            self.zeldaVisitHold = true
          else
            self:dismissZeldaVisit()
          end
        end, { waitButton = true }))
      end

      function state:startZeldaVisit(pages, onDone, keepAfter, reuseCurrent)
        self.zeldaDialog = {
          pages = pages or {},
          onDone = onDone,
          keepAfter = keepAfter == true,
        }
        self.zeldaVisitHold = true
        if reuseCurrent and (tonumber(self.zeldaTrainerX) or 160) <= self.zeldaTrainerTargetX then
          self.zeldaSlideMode = nil
          self:presentZeldaText()
        else
          self.zeldaTrainerX = 160
          self.zeldaSlideMode = "in"
          self.zeldaSlideChangedAt = nowSeconds()
        end
      end

      function state:dismissZeldaVisit()
        self.zeldaDialog = nil
        self.zeldaVisitHold = false
        if (tonumber(self.zeldaTrainerX) or 160) < 160 then
          self.zeldaSlideMode = "out"
          self.zeldaSlideChangedAt = nowSeconds()
        else
          self.zeldaSlideMode = nil
        end
      end

      function state:updateZeldaSlide()
        local mode = self.zeldaSlideMode
        if not mode then return end
        local now = nowSeconds()
        local elapsed = math.max(0, now - (self.zeldaSlideChangedAt or now))
        self.zeldaSlideChangedAt = now
        -- A deliberate screen-space slide, separate from the chunky babymon
        -- motion. The vanilla 56x56 POKEFAN F frontpic enters from offscreen.
        local speed = 120
        if mode == "in" then
          self.zeldaTrainerX = math.max(self.zeldaTrainerTargetX,
            (tonumber(self.zeldaTrainerX) or 160) - speed * elapsed)
          if self.zeldaTrainerX <= self.zeldaTrainerTargetX then
            self.zeldaTrainerX = self.zeldaTrainerTargetX
            self.zeldaSlideMode = nil
            self:presentZeldaText()
          end
        elseif mode == "out" then
          self.zeldaTrainerX = math.min(160,
            (tonumber(self.zeldaTrainerX) or self.zeldaTrainerTargetX) + speed * elapsed)
          if self.zeldaTrainerX >= 160 then
            self.zeldaTrainerX = 160
            self.zeldaSlideMode = nil
            self.zeldaVisitHold = false
            if self.zeldaOnboardingReleaseOnExit == true then
              self.zeldaOnboardingReleaseOnExit = false
              self.zeldaOnboardingLock = false
              self.data.zeldaTutorialFinishing = false
              self.data.zeldaTutorialSeen = true
              mod.save:set("babycare", self.data)
            end
          end
        end
      end

      function state:zeldaProactivePages()
        -- Automatic care tutorials are one-shot per gameplay concept, but CALL
        -- is deliberately different: if the current baby actually needs urgent
        -- help, Zelda will always discuss that live condition even if she has
        -- already taught that mechanic before. Otherwise CALL draws from a
        -- broader pool of conversational and mechanical tips.
        local slot = self:activeSlotRecord()

        -- A full ITEM pocket should not permanently forfeit Zelda's one-time
        -- max-Friendship gift. A later CALL retries the handoff.
        if self.data.friendshipEverstoneGiftPending == true
            and self.data.friendshipEverstoneGiftClaimed ~= true then
          local given = NEO.giveFirstFriendshipEverstone(self.game, self.data)
          if given then
            return {
              { "I still had this", "for you!" },
              { "ZELDA gave you", "an EVERSTONE!" },
              { "If you prefer to", "keep it a baby," },
              { "EVERSTONE should", "help with that!" },
            }
          end
          return {
            { "I still have a", "gift for you!" },
            { "Make some room in", "your ITEM pocket." },
            { "Then CALL me", "again, okay?" },
          }
        end

        -- While an Egg is incubating, Zelda can still be called. Give the
        -- player a little character moment plus a live hatch countdown.
        if slot and slot.kind == "egg" then
          local elapsed = eggElapsedMinutes(slot, self.game)
          local remain = math.max(0, math.ceil(NURSERY_CFG.EGG_HATCH_MINUTES - elapsed))
          local pages = {
            { "I'm curious what's", "inside that EGG!" },
          }
          if remain > 1 then
            pages[#pages + 1] = { "It should hatch in", tostring(remain) .. " minutes." }
          elseif remain == 1 then
            pages[#pages + 1] = { "It should hatch in", "about 1 minute." }
          else
            pages[#pages + 1] = { "It could hatch", "any moment now!" }
          end
          return pages
        end

        if slot and slot.kind == "baby" then
          local species = tostring(slot.species or "BABYMON")
          local sick = type(slot.sickness) == "table" and slot.sickness.kind or nil

          -- Live urgent-care help ignores the one-time auto-tip history.
          if sick then
            local pages = {
              { species .. " looks", "under the weather." },
            }
            if sick == "tummyache" then
              pages[#pages + 1] = { "For TUMMYACHE,", "try ANTIDOTE." }
            elseif sick == "tired" then
              pages[#pages + 1] = { "For TIRED,", "try AWAKENING." }
            elseif sick == "rash" then
              pages[#pages + 1] = { "For a RASH,", "try BURN HEAL." }
            elseif sick == "feverish" then
              pages[#pages + 1] = { "For FEVERISH,", "try ICE HEAL." }
            elseif sick == "famished" then
              pages[#pages + 1] = { "For SAPPED,", "try PARLYZ HEAL." }
            else
              pages[#pages + 1] = { "Check STATUS for", "the current COND." }
            end
            pages[#pages + 1] = { "FULL HEAL works", "for any illness." }
            return pages
          end

          local wasteCount = math.max(0,
            math.floor(tonumber(self.data.wasteCount) or (self.data.wastePresent and 1 or 0)))
          if wasteCount > 0 then
            return {
              { "There's a mess in", "the Nursery." },
              { "Use FLUSH to", "clean it up." },
            }
          end
          if clampMeter(self.data.hunger) == 0 then
            return {
              { species .. " is", "really hungry!" },
              { "Give it some", "FOOD right away." },
            }
          end
          if clampMeter(self.data.clean) == 0 then
            return {
              { "The room is", "very dirty now." },
              { "Use FLUSH when", "there is a mess." },
            }
          end
          if clampMeter(self.data.fun) == 0 then
            return {
              { "COND says BORED.", "That one's easy!" },
              { "Try one of the", "PLAY games." },
            }
          end
          if self:sleepWindowActive() then
            return {
              { "Looks like it's", "bedtime now." },
              { "When you see ZZZ,", "turn LIGHTS off." },
            }
          end

          local age = math.max(0, math.floor(tonumber(slot.ageDays) or 0))
          local wt = math.max(0, math.floor(tonumber(slot.weightTenths) or 0))
          local whole, tenth = math.floor(wt / 10), wt % 10
          local weightText = tenth == 0 and tostring(whole) or (tostring(whole) .. "." .. tostring(tenth))
          local seen = slot.preferencesDiscovered or {}
          local profile = NURSERY_CFG.PERSONALITY_PROFILES[slot.species]

          local tips = {
            { { "How is " .. species .. "?", "Doing okay?" } },
            { { species .. " is now", tostring(age) .. " days old." },
              { "They grow up", "so quickly!" } },
            { { species .. " weighs", weightText .. " LBS now." },
              { "FOOD adds weight.", "PLAY trims a bit." } },
            { { "Our EGGs come from", "special breeders." },
              { "Their SHINY odds", "are much better!" } },
            { { "Illness in COND", "needs the right MED." },
              { "FULL HEAL works", "for any of them." } },
            { { "Keep an eye on", "all 3 care meters." } },
            { { "Each BABYMON has", "its own favorites." },
              { "Try FOOD and PLAY", "to learn them." } },
            { { "STATUS shows age,", "weight, and COND." },
              { "Use LEFT/RIGHT", "to see more." } },
            { { "PAUSE CARE", "freezes all needs." } },
            { { "Most babies sleep", "around 9PM-9AM." },
              { "See the ZZZ?", "Turn LIGHTS off." } },
            { { "Good care builds", "FRIENDSHIP." },
              { "At 100, you can", "adopt the baby." } },
            { { "A HAPPY sign after", "MED means it helped." },
              { "A sad reaction", "means try another." } },
          }

          local condPages = self:zeldaConditionPages(slot)
          if condPages then tips[#tips + 1] = condPages end

          if profile and seen.favoriteFood == true then
            tips[#tips + 1] = {
              { species .. " really likes", foodLabel(profile.favoriteFood) .. "!" },
              { "Favorites can give", "extra FRIENDSHIP." },
            }
          end
          if profile and seen.favoriteGame == true then
            tips[#tips + 1] = {
              { species .. " really likes", tostring(profile.favoriteGame) .. "!" },
              { "Favorite games can", "help FRIENDSHIP." },
            }
          end

          local idx
          if love.math and love.math.random then idx = love.math.random(#tips) else idx = math.random(#tips) end
          return tips[idx]
        end

        -- No active resident: still give useful Nursery-wide advice.
        local tips = {
          { { "Our EGGs come from", "special breeders." },
            { "Their SHINY odds", "are much better!" } },
          { { "Different sickness", "needs different MED." },
            { "FULL HEAL works", "for any of them." } },
          { { "PAUSE CARE", "freezes all needs." } },
          { { "Good care builds", "FRIENDSHIP." },
            { "At 100, you can", "adopt the baby." } },
        }
        local idx
        if love.math and love.math.random then idx = love.math.random(#tips) else idx = math.random(#tips) end
        return tips[idx]
      end

      function state:openCallMenu()
        self.callMenu = { cursor = 1, contacts = NURSERY_CFG.CALL_CONTACTS }
      end

      function state:updateCallMenu(input)
        local menu = self.callMenu
        if not menu then return end
        local contacts = menu.contacts or NURSERY_CFG.CALL_CONTACTS
        local count = #contacts
        if input:wasPressed("b") then
          self.callMenu = nil
          return
        end
        if count <= 0 then
          if input:wasPressed("a") then self.callMenu = nil end
          return
        end
        if input:wasPressed("up") then
          menu.cursor = menu.cursor - 1
          if menu.cursor < 1 then menu.cursor = count end
        elseif input:wasPressed("down") then
          menu.cursor = menu.cursor + 1
          if menu.cursor > count then menu.cursor = 1 end
        elseif input:wasPressed("a") then
          local contact = contacts[menu.cursor]
          if contact and contact.id == "zelda" then
            -- Match the Pokegear outgoing-call cue (SFX_CALL / $6a). The call
            -- does not immediately open dialogue: it places Zelda's portrait
            -- in the lower-right pending slot for the player to answer.
            Sound.play(self.game.data, "Sfx_Call")
            self.data.callPendingContact = "zelda"
            self.callMenu = nil
          else
            Sound.play(self.game.data, "Sfx_Wrong")
          end
        end
      end

      function state:openZeldaProactiveHelp()
        self.data.callPendingContact = nil
        self:startZeldaVisit(self:zeldaProactivePages(), nil, false)
      end

      function state:currentZeldaCareKind()
        local slot = self:activeSlotRecord()
        if not slot or slot.kind ~= "baby" or self.data.carePaused == true then return nil end
        if type(slot.sickness) == "table" and slot.sickness.kind ~= nil then return "sickness" end
        local wasteCount = math.max(0, math.floor(tonumber(self.data.wasteCount) or (self.data.wastePresent and 1 or 0)))
        if wasteCount > 0 then return "poop" end
        if clampMeter(self.data.hunger) == 0 then return "hunger" end
        if clampMeter(self.data.clean) == 0 then return "clean" end
        if clampMeter(self.data.fun) == 0 then return "fun" end
        return nil
      end

      function state:refreshZeldaPendingTip()
        local kind = self.data.zeldaPendingTip
        if kind == nil then return nil end
        if kind == "friendship" then return kind end
        self.data.zeldaCareTipsSeen = self.data.zeldaCareTipsSeen or {}
        if self.data.zeldaCareTipsSeen[kind] == true then
          self.data.zeldaPendingTip = nil
          return nil
        end
        if kind == "bedtime" then
          if not self:sleepWindowActive() then self.data.zeldaPendingTip = nil end
          return self.data.zeldaPendingTip
        end
        local current = self:currentZeldaCareKind()
        if kind == "poop" then
          if current ~= "poop" then self.data.zeldaPendingTip = nil end
          return self.data.zeldaPendingTip
        end
        if kind == "sickness" then
          if current ~= "sickness" then self.data.zeldaPendingTip = nil end
          return self.data.zeldaPendingTip
        end
        if kind == "hunger" or kind == "clean" or kind == "fun" then
          if current ~= kind then self.data.zeldaPendingTip = nil end
          return self.data.zeldaPendingTip
        end
        return kind
      end

      function state:zeldaPortraitAvailable()
        local pending = self:refreshZeldaPendingTip()
        return self.data.callPendingContact == "zelda"
          or pending ~= nil or self:unseenZeldaCareKind() ~= nil
      end

      function state:openZeldaContextHelp()
        local kind = self:refreshZeldaPendingTip()
        if kind == nil then kind = self:unseenZeldaCareKind() end
        if kind == nil and self:sleepWindowActive() then
          self.data.zeldaCareTipsSeen = self.data.zeldaCareTipsSeen or {}
          if self.data.zeldaCareTipsSeen.bedtime ~= true then kind = "bedtime" end
        end

        local pages
        if kind == "friendship" then
          local event = self.data.friendshipMilestones and self.data.friendshipMilestones[1] or nil
          local unlocked = event and event.neoUnlock or nil
          pages = {
            { "You've reached full", "FRIENDSHIP!" },
            { "Visit me at the", "DAY CARE to adopt." },
          }

          if self.data.friendshipEverstoneGiftClaimed ~= true then
            local given, reason = NEO.giveFirstFriendshipEverstone(self.game, self.data)
            if given then
              pages[#pages + 1] = { "I have a little", "gift for you too!" }
              pages[#pages + 1] = { "ZELDA gave you", "an EVERSTONE!" }
              pages[#pages + 1] = { "If you prefer to", "keep it a baby," }
              pages[#pages + 1] = { "EVERSTONE should", "help with that!" }
            elseif reason == "FULL" then
              pages[#pages + 1] = { "I have a little", "gift for you too!" }
              pages[#pages + 1] = { "Your ITEM pocket", "is full right now." }
              pages[#pages + 1] = { "Make some room,", "then CALL me!" }
            end
          end

          if event and OFFICIAL_BABY_SPECIES[event.species] then
            pages[#pages + 1] = { "You've also unlocked", "SPRITE STYLE!" }
            pages[#pages + 1] = { "Check STATUS to", "switch its artwork." }
          end
          if unlocked then
            pages[#pages + 1] = { "I also discovered", "a new special EGG!" }
            pages[#pages + 1] = { tostring(unlocked) .. " EGG is", "under NEW EGG." }
          end
        elseif kind == "bedtime" then
          pages = {
            { "Your baby looks", "ready for bed." },
            { "Most babies sleep", "from 9PM to 9AM." },
            { "When you see ZZZ,", "turn LIGHTS off." },
            { "Good sleep helps", "keep it healthy." },
          }
        elseif kind == "poop" then
          pages = {
            { "Looks like your", "baby left a mess!" },
            { "Use FLUSH to", "clean it up." },
          }
        elseif kind == "sickness" then
          pages = {
            { "Your baby looks", "under the weather." },
            { "Open STATUS and", "check its COND." },
            { "An illness in", "COND needs MED." },
            { "Pick the remedy", "that fits it." },
            { "A correct remedy", "gets a HAPPY sign." },
            { "FULL HEAL works", "for any illness." },
          }
        elseif kind == "hunger" then
          pages = {
            { "That baby is", "really hungry!" },
            { "Try giving it", "some FOOD." },
          }
        elseif kind == "clean" then
          pages = {
            { "Things are getting", "pretty messy." },
            { "A good CLEAN will", "fix the room up." },
          }
        elseif kind == "fun" then
          pages = {
            { "Your baby could", "needs attention." },
            { "Try one of the", "PLAY games." },
          }
        else
          pages = {
            { "Everything looks", "okay for now." },
            { "Call me anytime", "if you need a tip." },
          }
        end

        if kind == "friendship" then
          self.data.friendshipMilestones = self.data.friendshipMilestones or {}
          if #self.data.friendshipMilestones > 0 then table.remove(self.data.friendshipMilestones, 1) end
          if #self.data.friendshipMilestones > 0 then
            self.data.zeldaPendingTip = "friendship"
          else
            self.data.zeldaPendingTip = nil
          end
        elseif kind then
          self.data.zeldaCareTipsSeen = self.data.zeldaCareTipsSeen or {}
          self.data.zeldaCareTipsSeen[kind] = true
          self.data.zeldaPendingTip = nil
        end
        self:startZeldaVisit(pages, nil, false)
      end

      function state:openZeldaHelp()
        -- Kept for old internal callers; CALL and contextual care alerts now
        -- both converge on the lower-right Zelda portrait before her visit.
        self:openZeldaContextHelp()
      end

      function state:beginZeldaOnboarding()
        self.data.hasBabyMonitor = true
        self.data.zeldaAccepted = true
        self.data.zeldaIntroAwaitingEgg = true
        self.data.zeldaTutorialFinishing = false
        self.zeldaOnboardingLock = true
        self.zeldaOnboardingReleaseOnExit = false
        self:startZeldaVisit({
          { "Let's get started!", "Use STATUS." },
          { "Choose NEW EGG.", "Pick an available EGG." },
          { "I'll stay here", "while you choose." },
        }, function()
          -- Put the selector directly on STATUS once Zelda finishes the first
          -- explanation. Other bottom icons remain visible, but pressing A on
          -- them gives only the normal negative beep during this guided step.
          self.cursor = 6
        end, true)
      end

      function state:finishZeldaOnboarding()
        self.data.zeldaIntroAwaitingEgg = false
        self.data.zeldaTutorialFinishing = true
        self.data.zeldaTutorialSeen = false
        self.zeldaOnboardingLock = true
        self.zeldaOnboardingReleaseOnExit = true
        self:startZeldaVisit({
          { "There it is!", "Wait for hatching." },
          { "If it gets hungry,", "feed it some FOOD." },
          { "Use PLAY so it has", "plenty of FUN." },
          { "Clean up any mess", "it leaves behind." },
          { "If COND shows", "an illness, use MED." },
          { "At night, use", "LIGHTS for sleep." },
          { "If you need me,", "use the CALL icon." },
          { "Then choose my", "portrait down here." },
          { "Good luck!", "Take good care!" },
        }, nil, false, true)
      end

      function state:updateZeldaDialog(input)
        -- Zelda's prose is handled by the engine's real Crystal TextBox at the
        -- bottom of the screen. Her pages are pre-wrapped into explicit
        -- two-line pages, so each page waits for A/B instead of ever invoking
        -- the TextBox's third-line vertical scroll.
        return self.zeldaTextBoxOpen == true
      end

      function state:drawZeldaTrainer()
        if not self:zeldaVisible() then return end
        local x = math.floor((tonumber(self.zeldaTrainerX) or 160) + 0.5)
        local image = self.art.zeldaTrainer
        if image then
          local G = love.graphics
          local function body()
            G.setColor(1, 1, 1, 1)
            -- +4px from the previous placement, matching the requested mockup.
            G.draw(image, x, 32)
          end
          local palettes = self.game and self.game.data and self.game.data.gen2Palettes
          local colors = palettes and Palettes.trainerColors(palettes, "POKEFANF") or nil
          -- The image already has an edge-only alpha cutout. Use the normal
          -- four-shade palette mapper so legitimate white pixels inside Zelda
          -- and the dolls remain visible instead of becoming transparent.
          if colors and GbcPalette.available() then GbcPalette.with(colors, body) else body() end
          G.setColor(1, 1, 1, 1)
        else
          drawImage(self.art.zelda, x, 72)
        end
      end

      function state:unseenZeldaCareKind()
        local kind = self:currentZeldaCareKind()
        if kind == nil then return nil end
        self.data.zeldaCareTipsSeen = self.data.zeldaCareTipsSeen or {}
        if self.data.zeldaCareTipsSeen[kind] == true then return nil end
        return kind
      end

      function state:hasAnyUrgentCareNeeds()
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          local slot = self.data.slots and self.data.slots[i]
          if slot and slot.kind == "baby" then
            if type(slot.sickness) == "table" and slot.sickness.kind ~= nil then return true end
            if math.max(0, math.floor(tonumber(slot.wasteCount)
                or (slot.wastePresent and 1 or 0))) > 0 then return true end
            if clampMeter(slot.hunger) == 0 then return true end
            if clampMeter(slot.clean) == 0 then return true end
            if clampMeter(slot.fun) == 0 then return true end
          end
        end
        return false
      end

      function state:careAlertNeeded()
        -- The top-left care alert is a state indicator, not a Zelda-tip flag.
        -- Reading a one-time tutorial therefore cannot dismiss it while this
        -- or another resident still has an urgent need.
        return self:hasAnyUrgentCareNeeds()
          or self:refreshZeldaPendingTip() ~= nil
      end

      function state:activeSlotRecord()
        return self.data.slots and self.data.slots[self.data.activeSlot or 1] or nil
      end

      function state:sleepWindowActive()
        return sleepWindowActiveFor(self.data, self.game)
      end

      function state:isSleeping()
        local slot = self:activeSlotRecord()
        -- Bedtime itself puts the baby to sleep. LIGHTS OFF is the player's
        -- responsibility for *good* sleep, but sickness, hunger, and a bright
        -- room never make a scheduled sleeping baby get up and wander around.
        return slot and slot.kind == "baby" and self:sleepWindowActive()
      end

      function state:persistentThoughtKind()
        -- Sleep wins over every care condition. A sick/hungry baby keeps that
        -- condition overnight, but visually it is sleeping and can be treated
        -- in the morning.
        if self:isSleeping() then return "exhausted" end
        local slot = self:activeSlotRecord()
        local sick = slot and slot.sickness
        if type(sick) == "table" and sick.kind then
          return sicknessThoughtKind(sick.kind)
        end
        if slot and slot.kind == "baby" then
          if clampMeter(self.data.hunger) == 0 then return "famished" end
          if clampMeter(self.data.fun) == 0 then return "sad" end
          if clampMeter(self.data.clean) == 0 then return "miserable" end
        end
        return nil
      end

      function state:showThought(kind, duration)
        if not (kind and self.art and self.art.thought and self.art.thought[kind]) then return end
        self.thoughtBubble = {
          kind = kind,
          untilAt = nowSeconds() + (tonumber(duration) or NURSERY_CFG.THOUGHT_SECONDS),
        }
      end

      function state:setTemporaryCondition(label, thought, duration)
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby" and label) then return end

        -- Player actions still get an immediate visual reaction, but they no
        -- longer replace COND on the spot. Instead they bias the next scheduled
        -- ambient roll for up to 30 minutes. This keeps the baby's visible COND
        -- stable enough to notice and remember.
        slot.conditionInfluence = tostring(label)
        slot.conditionInfluenceUntilAt = wallNow() + NEO.COND_INFLUENCE_SECONDS
        if thought then self:showThought(thought) end
        mod.save:set("babycare", self.data)
      end

      function state:conditionThoughtFor(label)
        if label == "LOVED" then return "happy" end
        if label == "PLAYFUL" then return "happy" end
        if label == "SATIATED" then return "relaxed" end
        if label == "FRESH" then return "happy" end
        if label == "RELAXED" then return "relaxed" end
        if label == "ENERGETIC" then return "ecstatic" end
        if label == "GRACEFUL" then return "happy" end
        if label == "DAYDREAMING" then return "relaxed" end
        if label == "CURIOUS" then return "curious" end
        if label == "ANGRY" then return "angry" end
        return nil
      end

      function state:rollAmbientCondition(force)
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then return false end
        if self.data.carePaused == true then return false end

        if slot.conditionForceRoll == true then
          force = true
          slot.conditionForceRoll = nil
        end

        local now = wallNow()
        local nextAt = tonumber(slot.conditionNextRollAt)
          or (now + NEO.COND_ROLL_SECONDS)
        if force ~= true and now < nextAt then return false end

        slot.conditionNextRollAt = now + NEO.COND_ROLL_SECONDS

        -- Urgent needs, illness and sleep have their own immediate CONDs. Do
        -- not churn a hidden flavor state while one of those is active.
        local sick = type(slot.sickness) == "table" and slot.sickness.kind or nil
        local hunger = clampMeter(slot.hunger)
        local fun = clampMeter(slot.fun)
        local clean = clampMeter(slot.clean)
        local waste = math.max(0, math.floor(tonumber(slot.wasteCount)
          or (slot.wastePresent and 1 or 0)))
        if sick or hunger <= 1 or fun <= 1 or clean <= 1 or waste > 0
            or self:sleepWindowActive() then
          mod.save:set("babycare", self.data)
          return false
        end

        -- Every 30 minutes we only have a 50% chance to actually reroll. Even a
        -- successful roll can land on the same flavor again, so visible changes
        -- usually happen less often than once per hour.
        if force ~= true and self:movementRandom() >= NEO.COND_ROLL_CHANCE then
          mod.save:set("babycare", self.data)
          return false
        end

        local choices = {}
        local function add(label, weight)
          choices[#choices + 1] = {
            label = label,
            weight = math.max(0, tonumber(weight) or 0),
          }
        end

        add("CONTENT", 1.2)
        add("CURIOUS", 0.9)
        add("DAYDREAMING", 0.8)

        if fun >= 3.5 then
          add("PLAYFUL", 1.8)
          add("ENERGETIC", 0.7)
        end
        if hunger >= 3.5 then add("SATIATED", 1.6) end
        if clean >= 3.5 then add("FRESH", 1.4) end
        if clampHappiness(slot.happiness or 0) >= 80 then add("LOVED", 2.2) end

        local influenceUntil = tonumber(slot.conditionInfluenceUntilAt) or 0
        if slot.conditionInfluence and now < influenceUntil then
          add(tostring(slot.conditionInfluence), 4.0)
        else
          slot.conditionInfluence = nil
          slot.conditionInfluenceUntilAt = nil
        end

        local total = 0
        for _, choice in ipairs(choices) do total = total + choice.weight end
        if total <= 0 then return false end

        local roll = self:movementRandom() * total
        local selected = choices[#choices].label
        local acc = 0
        for _, choice in ipairs(choices) do
          acc = acc + choice.weight
          if roll <= acc then
            selected = choice.label
            break
          end
        end

        local changed = slot.conditionAmbient ~= selected
        slot.conditionAmbient = selected
        mod.save:set("babycare", self.data)

        if changed then
          local thought = self:conditionThoughtFor(selected)
          if thought then self:showThought(thought) end
        end
        return changed
      end

      function state:currentConditionLabel(slot)
        slot = slot or self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then return "NONE" end

        local sick = type(slot.sickness) == "table" and slot.sickness.kind or nil
        if sick then return sicknessLabel(sick) end

        local hunger = clampMeter(slot.hunger)
        local fun = clampMeter(slot.fun)
        local clean = clampMeter(slot.clean)
        local waste = math.max(0, math.floor(tonumber(slot.wasteCount)
          or (slot.wastePresent and 1 or 0)))

        -- Care-need CONDs remain immediate and state-based. Flavor CONDs are the
        -- slow, discoverable layer underneath them.
        if hunger <= 1 then return "HUNGRY" end
        if waste > 0 or clean <= 1 then return "DIRTY" end
        if fun <= 1 then return "BORED" end

        if slot == self:activeSlotRecord() and self:sleepWindowActive() then
          return self.data.lightsOn == false and "RESTING" or "SLEEPY"
        end

        return tostring(slot.conditionAmbient or "CONTENT")
      end

      function state:zeldaConditionPages(slot)
        local cond = self:currentConditionLabel(slot)
        local species = tostring(slot and slot.species or "BABYMON")
        if cond == "LOVED" then
          return { { species .. " really", "trusts you now." } }
        elseif cond == "PLAYFUL" then
          return { { species .. " looks", "very playful!" } }
        elseif cond == "SATIATED" then
          return { { species .. " looks", "nice and full." } }
        elseif cond == "FRESH" then
          return { { species .. " looks", "fresh and clean." } }
        elseif cond == "RELAXED" then
          return { { species .. " looks", "nice and relaxed." } }
        elseif cond == "ENERGETIC" then
          return { { species .. " has", "lots of energy!" } }
        elseif cond == "GRACEFUL" then
          return { { "Did you see those", "moves? So graceful!" } }
        elseif cond == "DAYDREAMING" then
          return { { species .. " seems", "lost in thought." } }
        elseif cond == "CURIOUS" then
          return { { species .. " seems", "curious today." } }
        elseif cond == "ANGRY" then
          return { { species .. " seems", "a little grumpy." } }
        end
        return nil
      end

      function state:updateThought()
        local bubble = self.thoughtBubble
        if bubble and nowSeconds() >= (tonumber(bubble.untilAt) or 0) then
          self.thoughtBubble = nil
        end
      end

      function state:showCriticalNeedThought()
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then return end
        if clampMeter(self.data.hunger) == 0 then
          self:showThought("famished")
        elseif clampMeter(self.data.fun) == 0 then
          self:showThought("sad")
        elseif clampMeter(self.data.clean) == 0 then
          self:showThought("miserable")
        end
      end

      function state:syncActiveSlot()
        local slot = self:activeSlotRecord()
        if not slot or slot.kind ~= "baby" then return end
        slot.hunger = clampMeter(self.data.hunger)
        slot.fun = clampMeter(self.data.fun)
        slot.clean = clampMeter(self.data.clean)
        slot.careRemainder = {
          hunger = tonumber(self.data.careRemainder and self.data.careRemainder.hunger) or 0,
          fun = tonumber(self.data.careRemainder and self.data.careRemainder.fun) or 0,
          clean = tonumber(self.data.careRemainder and self.data.careRemainder.clean) or 0,
        }
        slot.wasteCount = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
          math.floor(tonumber(self.data.wasteCount) or (self.data.wastePresent and 1 or 0))))
        slot.wastePresent = slot.wasteCount > 0
        slot.wasteExposure = math.max(0, tonumber(self.data.wasteExposure) or 0)
        slot.wastePenalty = tonumber(self.data.wastePenalty) or 0
        slot.digestion = math.max(0, tonumber(self.data.digestion) or 0)
        slot.poopDueAt = tonumber(self.data.poopDueAt)
        slot.poopPendingWake = self.data.poopPendingWake == true
        slot.devPoopQueued = self.data.devPoopQueued == true
        slot.dietStrain = tonumber(self.data.dietStrain) or 0
        slot.sicknessRisk = self.data.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
        slot.sickness = self.data.sickness
        slot.sleepWalkIndex = tonumber(self.data.sleepWalkIndex)
        slot.sleepGoodSeconds = math.max(0, tonumber(self.data.sleepGoodSeconds) or 0)
        slot.sleepWasWindow = self.data.sleepWasWindow == true
        slot.careLastRealAt = tonumber(self.data.careLastRealAt) or wallNow()
        normalizeWellnessState(slot)
        normalizeWellnessState(self.data)
        -- The illness pass consumes this later. 0 = spotless, 1 = fully dirty.
        slot.sicknessSusceptibility = math.max(0, math.min(1, (4 - clampMeter(self.data.clean)) / 4))
        NEO.syncNurseryMonMetadata(slot, slot.nurseryMon)
      end

      function state:loadSlot(index, replacingCurrentSlot)
        index = math.max(1, math.min(NURSERY_CFG.SLOT_COUNT, math.floor(tonumber(index) or 1)))
        local slot = self.data.slots and self.data.slots[index]
        if not slot then return false end

        local now = wallNow()
        -- Settle and persist the resident we are leaving before changing the
        -- active index. This keeps its personal care clock current.
        --
        -- Exception: hatchEgg() has already replaced the active Egg record with
        -- a newborn baby. In that case the top-level HUD still contains the
        -- Egg's quiet 4/4/4 placeholder values. Syncing those into the newborn
        -- here would erase its intended 2 FOOD / 2 FUN / 4 CLEAN starting state.
        if replacingCurrentSlot ~= true then
          local outgoing = self:activeSlotRecord()
          if outgoing and outgoing.kind == "baby" then
            advanceCareClock(self.data, now, true, self.game)
          end
          self:syncActiveSlot()
        end

        self.data.activeSlot = index
        if slot.kind == "baby" then
          self.data.hunger = clampMeter(slot.hunger == nil and 4 or slot.hunger)
          self.data.fun = clampMeter(slot.fun == nil and 4 or slot.fun)
          self.data.clean = clampMeter(slot.clean == nil and 4 or slot.clean)
          self.data.careRemainder = slot.careRemainder or { hunger = 0, fun = 0, clean = 0 }
          self.data.wasteCount = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
            math.floor(tonumber(slot.wasteCount) or (slot.wastePresent and 1 or 0))))
          self.data.wastePresent = self.data.wasteCount > 0
          self.data.wasteExposure = math.max(0, tonumber(slot.wasteExposure) or 0)
          self.data.wastePenalty = tonumber(slot.wastePenalty) or 0
          self.data.digestion = math.max(0, tonumber(slot.digestion) or 0)
          self.data.poopDueAt = tonumber(slot.poopDueAt)
          self.data.poopPendingWake = slot.poopPendingWake == true
          self.data.devPoopQueued = slot.devPoopQueued == true
          self.data.dietStrain = tonumber(slot.dietStrain) or 0
          self.data.sicknessRisk = slot.sicknessRisk or { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
          self.data.sickness = slot.sickness
          self.data.sleepWalkIndex = tonumber(slot.sleepWalkIndex)
          self.data.sleepGoodSeconds = math.max(0, tonumber(slot.sleepGoodSeconds) or 0)
          self.data.sleepWasWindow = slot.sleepWasWindow == true
          self.data.careLastRealAt = tonumber(slot.careLastRealAt) or now
          normalizeWellnessState(self.data)

          -- Lazy catch-up: inactive residents keep accumulating real-world care
          -- time even though only the selected slot is rendered. Apply that
          -- resident's elapsed Hunger/Fun/digestion/etc. when selected, then
          -- save the new checkpoint back onto the slot.
          advanceCareClock(self.data, now, true, self.game)
          self:syncActiveSlot()
        else
          -- Eggs have no needs yet. Keep the HUD full/quiet while the egg is
          -- the active Nursery resident and restart the care checkpoint so an
          -- eventual hatch never inherits elapsed neglect from the prior baby.
          self.data.hunger, self.data.fun, self.data.clean = 4, 4, 4
          self.data.careRemainder = { hunger = 0, fun = 0, clean = 0 }
          self.data.wastePresent, self.data.wasteCount, self.data.wasteExposure, self.data.wastePenalty = false, 0, 0, 0
          self.data.digestion, self.data.poopDueAt, self.data.poopPendingWake, self.data.devPoopQueued = 0, nil, false, false
          self.data.dietStrain = 0
          self.data.sicknessRisk = { tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0 }
          self.data.sickness = nil
          self.data.sleepWalkIndex = nil
          self.data.sleepGoodSeconds = 0
          self.data.sleepWasWindow = false
          self.data.careLastRealAt = now
        end
        self.careClockPolledAt = self.data.careLastRealAt
        if self.data.carePaused == true then
          self.babyWalkIndex = persistedBabyWalkIndex(self.data) or self.babyWalkIndex or randomBabyWalkIndex()
        else
          self.babyWalkIndex = randomBabyWalkIndex()
        end
        self.babyWalkChangedAt = nowSeconds()
        self.thoughtBubble = nil
        self.wasteFrame = 1
        self.wasteChangedAt = nowSeconds()
        return true
      end

      function state:updateAges()
        if self.data.carePaused == true then return end
        local now = wallNow()
        for _, slot in ipairs(self.data.slots or {}) do
          if type(slot) == "table" and slot.kind == "baby" then
            local born = tonumber(slot.birthRealAt)
            if born == nil or born <= 0 or born > now then
              local legacyAge = math.max(0, math.floor(tonumber(slot.ageDays) or 0))
              -- v0.0.84 and earlier tracked age against gameMinuteStamp(). That
              -- value lives in two incompatible clock domains: PokeSurvive's
              -- run-day clock starts near day 0, while vanilla fallback is Unix
              -- epoch minutes. Switching profiles could therefore turn a one-day
              -- baby into a 20,000-day cryptid. Migrate impossible values from
              -- the most recent Nursery Egg claim when available; otherwise keep
              -- a sane legacy age and anchor it to real time from here forward.
              if legacyAge >= 3650 then
                local claim = tonumber(self.data.lastEggClaimRealAt) or 0
                if slot.origin == "nursery" and claim > 0 and claim <= now
                    and (now - claim) <= (365 * 24 * 60 * 60) then
                  born = claim
                else
                  born = now
                end
              else
                born = now - legacyAge * 24 * 60 * 60
              end
              slot.birthRealAt = born
              slot.birthGameDay = nil
            end
            slot.ageDays = math.max(0, math.floor((now - born) / (24 * 60 * 60)))
          end
        end
      end

      function state:updateHappiness(_elapsed)
        -- Passive Friendship now advances inside advanceCareClock so it also
        -- works while the player is in the overworld or the Nursery is closed.
        -- This compatibility stub remains for older call sites in this screen.
      end

      function state:eggChoices()
        -- ODD EGG remains the canonical eight-baby mystery pool. Every Neo
        -- discovery becomes a permanent, separately selectable coloured Egg.
        local out = { { id = "RANDOM", label = "ODD EGG" } }
        local unlocked = self.data.unlockedNeoBabies or {}
        for _, id in ipairs(NURSERY_CFG.NEO.pool) do
          if unlocked[id] == true then
            out[#out + 1] = { id = id, label = id .. " EGG", neo = true }
          end
        end
        return out
      end

      function state:firstOpenSlot()
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          if not self.data.slots[i] then return i end
        end
        return nil
      end

      function state:eggCooldownReady()
        local last = tonumber(self.data.lastEggClaimRealAt) or 0
        return last <= 0 or wallNow() - last >= NURSERY_CFG.EGG_COOLDOWN_SECONDS
      end

      function state:eggCooldownHoursLeft()
        local last = tonumber(self.data.lastEggClaimRealAt) or 0
        if last <= 0 then return 0 end
        local remaining = NURSERY_CFG.EGG_COOLDOWN_SECONDS - (wallNow() - last)
        if remaining <= 0 then return 0 end
        return math.max(1, math.ceil(remaining / 3600))
      end

      function state:hasUnlockedEgg()
        for id, yes in pairs(self.data.unlockedEggs or {}) do
          if yes and BABY_DEFS[id] then return true end
        end
        return false
      end

      function state:claimEgg(choice)
        if not self:eggCooldownReady() then
          local hours = self:eggCooldownHoursLeft()
          Sound.play(self.game.data, "Sfx_Wrong")
          local waitLine = "You must wait " .. tostring(hours)
          self.game.stack:push(TextBox.new(self.game, vanillaPages({
            { waitLine, "hours before" },
            { "choosing a new EGG.", "" },
          }), nil, { waitButton = true }))
          return false
        end
        local open = self:firstOpenSlot()
        if not open then
          Sound.play(self.game.data, "Sfx_Wrong")
          return false
        end
        local target = choice and choice.id or "RANDOM"
        local hatchSpecies
        if target ~= "RANDOM" and NURSERY_CFG.NEO.species[target]
          and self.data.unlockedNeoBabies and self.data.unlockedNeoBabies[target] == true then
          hatchSpecies = target
        else
          target = "RANDOM"
          hatchSpecies = randomOfficialBaby()
        end
        if not BABY_DEFS[hatchSpecies] then hatchSpecies = randomOfficialBaby() end
        local eggDvs, rolledShiny = NURSERY_CFG.NEO.rollEggDVs()
        if self.data.forceNextShinyEgg == true then
          eggDvs = NURSERY_CFG.NEO.shinyDVs()
          rolledShiny = true
          self.data.forceNextShinyEgg = false
        end
        self:syncActiveSlot()
        self.data.slots[open] = {
          kind = "egg",
          origin = "nursery",
          eggChoice = target,
          hatchSpecies = hatchSpecies,
          dvs = eggDvs,
          shiny = rolledShiny,
          startedMinute = gameMinuteStamp(self.game),
          startedRealAt = wallNow(),
          readyMinute = gameMinuteStamp(self.game) + NURSERY_CFG.EGG_HATCH_MINUTES,
        }
        self.data.lastEggClaimRealAt = wallNow()
        self.data.eggClaims = (tonumber(self.data.eggClaims) or 0) + 1
        self:loadSlot(open)
        Sound.play(self.game.data, "Sfx_Menu")
        self.careMenu = nil
        if self.data.zeldaIntroAwaitingEgg == true then self:finishZeldaOnboarding() end
        return true
      end

      function state:hatchEgg(slotIndex, slot, mon, hatchRealAt)
        local species = mon and mon.species or slot.hatchSpecies or slot.sourceSpecies
        if not mon then
          mon = newNurseryMon(self.game, species, slot.origin == "player" and slot.sourceEgg or nil)
        end
        if not mon then
          self.hatchInProgress = false
          return false
        end
        local baby = nurseryBabyFromMon(mon, slot.origin or "nursery")
        local bornAt = tonumber(hatchRealAt) or wallNow()
        baby.birthRealAt = bornAt
        baby.careLastRealAt = bornAt
        baby.birthGameDay = nil
        baby.ageDays = 0
        self.data.slots[slotIndex] = baby
        if self.game and self.game.save then Breeding.markPokedex(self.game.save, species) end
        if slotIndex == self.data.activeSlot then
          -- The active slot changed identity from Egg -> baby. Load it without
          -- syncing the Egg HUD's full placeholder meters back into the newborn.
          self:loadSlot(slotIndex, true)
        end
        mod.save:set("babycare", self.data)
        return true
      end

      function state:prepareEggHatch(slot)
        if not (slot and slot.kind == "egg") then return nil, nil end
        local species, mon
        if slot.origin == "player" then
          species = slot.sourceSpecies or (slot.sourceEgg and slot.sourceEgg.species)
          mon = newNurseryMon(self.game, species, slot.sourceEgg)
        else
          species = slot.hatchSpecies
          if not BABY_DEFS[species] then
            species = randomOfficialBaby()
            slot.hatchSpecies = species
          end
          local eggRecord = { dvs = slot.dvs, shiny = slot.shiny == true }
          mon = newNurseryMon(self.game, species, eggRecord)
          if not mon then
            species = randomOfficialBaby()
            slot.hatchSpecies = species
            mon = newNurseryMon(self.game, species, eggRecord)
          end
        end
        return species, mon
      end

      function state:beginEggHatch(slotIndex, slot)
        if self.hatchInProgress then return end
        local species, mon = self:prepareEggHatch(slot)
        if not (species and mon) then return end
        self.hatchInProgress = true
        local game = self.game
        local function finish()
          if game and game.stack then game.stack:pop() end
          self:hatchEgg(slotIndex, slot, mon)
          self.hatchInProgress = false
          Music.play(game.data, "Music_Printer", true, { reason = "direct" })
          local def = game.data and game.data.pokemon and game.data.pokemon[species]
          local name = (def and def.name) or species
          Sound.play(game.data, "Sfx_CaughtMon")
          -- Live Nursery hatches are fully hands-off: the result line types,
          -- lingers briefly, then dismisses itself back to the Nursery.
          game.stack:push(TextBox.new(game,
            tostring(name) .. " came\nout of its EGG!", nil,
            { auto = { delay = 30 } }))
        end
        local function startAnimation()
          Screens.push(game, "Gen2EggHatchAnim", {
            mon = mon, species = species,
            menuGfx = game.data and game.data.gen2MenuGfx,
            onDone = finish,
          })
        end
        if game and game.stack then
          -- When the player is actually watching at the ten-minute mark, show
          -- a short vanilla dialogue box and continue automatically into the
          -- hatch animation. No A press is required anywhere in the sequence.
          game.stack:push(TextBox.new(game, "Oh! The EGG is\nhatching!",
            startAnimation, { auto = { delay = 30 } }))
        else
          self:hatchEgg(slotIndex, slot, mon)
          self.hatchInProgress = false
        end
      end

      function state:resolveReadyEggsOffscreen()
        -- Opening the Baby Monitor after an egg's incubation already finished
        -- should feel like checking a Tamagotchi: the baby has hatched while
        -- the player was away, so there is no retroactive cutscene to watch.
        --
        -- Important: if several real-world hours passed while the game was
        -- closed, the resident has also existed for the time *after* the egg's
        -- ten-minute hatch point. Preserve that hatch timestamp and immediately
        -- catch its care meters up instead of spawning a freshly-full baby at
        -- the moment the player reopens the Monitor.
        if self.data.carePaused == true then return end
        local now = wallNow()
        local hatchedAny = false
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          local slot = self.data.slots and self.data.slots[i]
          if slot and slot.kind == "egg"
             and eggElapsedMinutes(slot, self.game) >= NURSERY_CFG.EGG_HATCH_MINUTES then
            local _, mon = self:prepareEggHatch(slot)
            if mon then
              local hatchAt = now
              local startedRealAt = tonumber(slot.startedRealAt)
              if startedRealAt then
                local realReadyAt = startedRealAt + (NURSERY_CFG.EGG_HATCH_MINUTES * 60)
                -- If a synthetic in-game clock jump made the egg ready sooner
                -- than ten real minutes, don't invent care time in the future.
                hatchAt = math.min(now, realReadyAt)
              end
              if self:hatchEgg(i, slot, mon, hatchAt) then hatchedAny = true end
            end
          end
        end
        if hatchedAny then
          advanceAllResidentCare(self.data, now, self.game, false)
          copySlotToTopLevel(self.data, self.data.activeSlot or 1)
          self.data.careLastRealAt = now
          self.careClockPolledAt = now
          mod.save:set("babycare", self.data)
        end
      end

      function state:updateEggs()
        if self.data.carePaused == true or self.hatchInProgress then return end
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          local slot = self.data.slots and self.data.slots[i]
          if slot and slot.kind == "egg" and eggElapsedMinutes(slot, self.game) >= NURSERY_CFG.EGG_HATCH_MINUTES then
            self:beginEggHatch(i, slot)
            return
          end
        end
      end

      function state:openCareMenu()
        self:syncActiveSlot()
        Sound.play(self.game.data, "Sfx_Menu")
        local tutorialCursor = self.data.zeldaIntroAwaitingEgg == true and 2 or 1
        self.careMenu = {
          page = "main", cursor = tutorialCursor, offset = 1, eggChoice = 1,
          slotCursor = self.data.activeSlot or 1, pauseCursor = 1,
        }
      end

      function state:keepCareCursorVisible(menu)
        menu.offset = math.max(1, math.floor(tonumber(menu.offset) or 1))
        if menu.cursor < menu.offset then menu.offset = menu.cursor end
        local bottom = menu.offset + NURSERY_CFG.CARE_VISIBLE_ROWS - 1
        if menu.cursor > bottom then menu.offset = menu.cursor - NURSERY_CFG.CARE_VISIBLE_ROWS + 1 end
        local maxOffset = math.max(1, #NURSERY_CFG.CARE_ITEMS - NURSERY_CFG.CARE_VISIBLE_ROWS + 1)
        if menu.offset > maxOffset then menu.offset = maxOffset end
      end

      function state:togglePauseCare()
        local now = wallNow()
        local gameNow = gameMinuteStamp(self.game)
        if self.data.carePaused == true then
          local pausedGameAt = tonumber(self.data.carePauseGameMinute) or gameNow
          local gameDelta = math.max(0, gameNow - pausedGameAt)
          local pausedRealAt = tonumber(self.data.carePauseRealAt) or now
          local realDelta = math.max(0, now - pausedRealAt)
          -- PAUSE CARE is a true Nursery-wide freeze. Move egg, age, resident
          -- care checkpoints, and any pending poop timer forward by the paused
          -- duration so no slot accumulates hidden neglect while frozen.
          local pausedDays = math.floor(gameDelta / (24 * 60))
          for i = 1, NURSERY_CFG.SLOT_COUNT do
            local slot = self.data.slots[i]
            if slot and slot.kind == "egg" then
              if tonumber(slot.startedMinute) then slot.startedMinute = slot.startedMinute + gameDelta end
              if tonumber(slot.readyMinute) then slot.readyMinute = slot.readyMinute + gameDelta end
              if tonumber(slot.startedRealAt) then slot.startedRealAt = slot.startedRealAt + realDelta end
            elseif slot and slot.kind == "baby" then
              slot.careLastRealAt = (tonumber(slot.careLastRealAt) or pausedRealAt) + realDelta
              if tonumber(slot.poopDueAt) then slot.poopDueAt = tonumber(slot.poopDueAt) + realDelta end
              if tonumber(slot.birthRealAt) then
                slot.birthRealAt = tonumber(slot.birthRealAt) + realDelta
              elseif pausedDays > 0 and tonumber(slot.birthGameDay) then
                slot.birthGameDay = slot.birthGameDay + pausedDays
              end
              if tonumber(slot.conditionNextRollAt) then
                slot.conditionNextRollAt = tonumber(slot.conditionNextRollAt) + realDelta
              end
              if tonumber(slot.conditionInfluenceUntilAt) then
                slot.conditionInfluenceUntilAt = tonumber(slot.conditionInfluenceUntilAt) + realDelta
              end
            end
          end
          self.data.carePaused = false
          self.data.carePauseGameMinute = nil
          self.data.carePauseRealAt = nil
          self.data.pausedBabyWalkIndex = nil
          self.data.pausedBabyStep = nil
          self.movementFlourish = nil
          copySlotToTopLevel(self.data, self.data.activeSlot or 1)
          self.babyWalkChangedAt = nowSeconds()
        else
          -- Settle every resident exactly to the pause boundary first.
          advanceAllResidentCare(self.data, now, self.game, true)
          self.data.carePaused = true
          self.data.carePauseGameMinute = gameNow
          self.data.carePauseRealAt = now
          self.data.pausedBabyWalkIndex = math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
            math.floor(tonumber(self.babyWalkIndex) or 1)))
          local frozen = self:currentMovementStep()
          if frozen then
            self.data.pausedBabyStep = {
              frame = frozen.frame, x = frozen.x, y = frozen.y, flip = frozen.flip == true,
              back = frozen.back == true, rotation = tonumber(frozen.rotation) or 0,
            }
          end
          self.movementFlourish = nil
        end
        self.data.careLastRealAt = now
        self.careClockPolledAt = now
        Sound.play(self.game.data, "Sfx_SwitchPockets")
      end

      function state:careMainLabel(index)
        if index == 4 then return self.data.carePaused and "RESUME CARE" or "PAUSE CARE" end
        return NURSERY_CFG.CARE_ITEMS[index]
      end

      function state:updateCareMenu(input)
        local menu = self.careMenu
        if not menu then return end
        local page = menu.page
        if page == "main" and self.data.carePaused == true then
          local count = 3
          menu.pauseCursor = math.max(1, math.min(count, math.floor(tonumber(menu.pauseCursor) or 1)))
          if input:wasPressed("b") then self.careMenu = nil return end
          if input:wasPressed("up") then
            menu.pauseCursor = menu.pauseCursor - 1
            if menu.pauseCursor < 1 then menu.pauseCursor = count end
          elseif input:wasPressed("down") then
            menu.pauseCursor = menu.pauseCursor + 1
            if menu.pauseCursor > count then menu.pauseCursor = 1 end
          elseif input:wasPressed("a") then
            if menu.pauseCursor == 1 then
              menu.page = "status"
              menu.statusPage = 1
            elseif menu.pauseCursor == 2 then
              self:togglePauseCare()
              menu.cursor, menu.offset = 1, 1
            else
              self.careMenu = nil
            end
          end
          return
        end

        if page == "main" then
          if input:wasPressed("b") then
            self.careMenu = nil
            return
          end
          if input:wasPressed("up") then
            menu.cursor = menu.cursor - 1; if menu.cursor < 1 then menu.cursor = #NURSERY_CFG.CARE_ITEMS end
            self:keepCareCursorVisible(menu)
          elseif input:wasPressed("down") then
            menu.cursor = menu.cursor + 1; if menu.cursor > #NURSERY_CFG.CARE_ITEMS then menu.cursor = 1 end
            self:keepCareCursorVisible(menu)
          elseif input:wasPressed("a") then
            if self.data.zeldaIntroAwaitingEgg == true then
              if menu.cursor == 2 then
                menu.page = "egg"
                menu.eggChoice = 1
              else
                Sound.play(self.game.data, "Sfx_Wrong")
              end
              return
            end
            if menu.cursor == 1 then menu.page = "status"; menu.statusPage = 1
            elseif menu.cursor == 2 then menu.page = "egg"; menu.eggChoice = 1
            elseif menu.cursor == 3 then menu.page = "switch"; menu.slotCursor = self.data.activeSlot or 1
            elseif menu.cursor == 4 then self:togglePauseCare()
            else self.careMenu = nil end
          end
          return
        end

        if page == "status" then
          local slot = self:activeSlotRecord()
          local mastered = slot and slot.kind == "baby" and OFFICIAL_BABY_SPECIES[slot.species]
            and self.data.friendshipMasteredSpecies and self.data.friendshipMasteredSpecies[slot.species] == true
          local pageCount = mastered and 4 or 3
          menu.statusPage = math.max(1, math.min(pageCount, math.floor(tonumber(menu.statusPage) or 1)))
          if input:wasPressed("left") then
            menu.statusPage = menu.statusPage - 1
            if menu.statusPage < 1 then menu.statusPage = pageCount end
          elseif input:wasPressed("right") then
            menu.statusPage = menu.statusPage + 1
            if menu.statusPage > pageCount then menu.statusPage = 1 end
          elseif input:wasPressed("a") and menu.statusPage == 4 and mastered then
            slot.spriteStyle = slot.spriteStyle == "crystal" and "nursery" or "crystal"
            NEO.syncNurseryMonMetadata(slot, slot.nurseryMon)
            Sound.play(self.game.data, "Sfx_SwitchPockets")
          elseif input:wasPressed("a") or input:wasPressed("b") then
            menu.page = "main"
          end
          return
        end

        if page == "egg" then
          local choices = self:eggChoices()
          if #choices == 0 then choices = { { id = "RANDOM", label = "ODD EGG" } } end
          if menu.eggChoice > #choices then menu.eggChoice = #choices end
          if input:wasPressed("b") then menu.page = "main" return end
          if input:wasPressed("left") then
            menu.eggChoice = menu.eggChoice - 1; if menu.eggChoice < 1 then menu.eggChoice = #choices end
          elseif input:wasPressed("right") then
            menu.eggChoice = menu.eggChoice + 1; if menu.eggChoice > #choices then menu.eggChoice = 1 end
          elseif input:wasPressed("a") then
            self:claimEgg(choices[menu.eggChoice])
          end
          return
        end

        if page == "switch" then
          if input:wasPressed("b") then menu.page = "main" return end
          if input:wasPressed("up") then
            menu.slotCursor = menu.slotCursor - 1; if menu.slotCursor < 1 then menu.slotCursor = NURSERY_CFG.SLOT_COUNT end
          elseif input:wasPressed("down") then
            menu.slotCursor = menu.slotCursor + 1; if menu.slotCursor > NURSERY_CFG.SLOT_COUNT then menu.slotCursor = 1 end
          elseif input:wasPressed("a") then
            if self.data.slots[menu.slotCursor] then
              if menu.slotCursor ~= self.data.activeSlot then
                self:loadSlot(menu.slotCursor)
                Sound.play(self.game.data, "Sfx_SwitchPockets")
              else
                Sound.play(self.game.data, "Sfx_Menu")
              end
              self.careMenu = nil
            else
              Sound.play(self.game.data, "Sfx_Wrong")
            end
          end
          return
        end
      end

      function state:startNoRefusal()
        self.foodMenu = nil
        self.playMenu = nil
        self.medicineMenu = nil
        Sound.play(self.game.data, "Sfx_Wrong")
        if self:isSleeping() then
          -- Sleeping takes visual precedence: keep the bassinet + ZZZ bubble
          -- unchanged instead of waking the baby into a refusal pose.
          return
        end
        self:showThought("no")
        self.refusing = {
          index = 1,
          changedAt = nowSeconds(),
        }
      end

      function state:startRefusingFood()
        self:startNoRefusal()
      end

      function state:updateRefusingFood()
        local refuse = self.refusing
        if not refuse then return end
        local now = nowSeconds()
        local elapsed = now - refuse.changedAt
        if elapsed < NURSERY_CFG.REFUSE_STEP_SECONDS then return end
        local whole = math.floor(elapsed / NURSERY_CFG.REFUSE_STEP_SECONDS)
        refuse.index = refuse.index + whole
        refuse.changedAt = refuse.changedAt + whole * NURSERY_CFG.REFUSE_STEP_SECONDS
        if refuse.index > #NURSERY_CFG.FULL_HUNGER_REFUSE then
          self.refusing = nil
          self.babyWalkIndex = randomBabyWalkIndex()
          self.babyWalkChangedAt = nowSeconds()
        end
      end

      function state:schedulePoopIfReady(baseNow)
        local count = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
          math.floor(tonumber(self.data.wasteCount) or 0)))
        if count >= NURSERY_CFG.WASTE_MAX then
          self.data.digestion = math.min(math.max(0, tonumber(self.data.digestion) or 0), 1)
          self.data.poopDueAt = nil
          self.data.poopPendingWake = false
          return false
        end

        -- Sleeping babies never start or finish a bowel-movement timer. Hold
        -- one pending poop at most, then begin the normal 1-5 minute countdown
        -- only after wake-up.
        if self:isSleeping() then
          if (tonumber(self.data.digestion) or 0) >= 1
              or tonumber(self.data.poopDueAt) ~= nil
              or self.data.poopPendingWake == true then
            self.data.digestion = 1
            self.data.poopPendingWake = true
            self.data.poopDueAt = nil
          end
          return false
        end

        if self.data.poopPendingWake == true then
          self.data.poopPendingWake = false
          self.data.digestion = math.max(1, tonumber(self.data.digestion) or 0)
          self.data.poopDueAt = nil
        end
        if (tonumber(self.data.digestion) or 0) < 1 or tonumber(self.data.poopDueAt) ~= nil then
          return false
        end
        local delay
        if love.math and love.math.random then
          delay = love.math.random(NURSERY_CFG.POOP_DELAY_MIN_SECONDS, NURSERY_CFG.POOP_DELAY_MAX_SECONDS)
        else
          delay = math.random(NURSERY_CFG.POOP_DELAY_MIN_SECONDS, NURSERY_CFG.POOP_DELAY_MAX_SECONDS)
        end
        self.data.poopDueAt = (tonumber(baseNow) or wallNow()) + delay
        return true
      end

      function state:startPooping(forceDev)
        local active = self:activeSlotRecord()
        local count = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
          math.floor(tonumber(self.data.wasteCount) or 0)))
        if not (active and active.kind == "baby") or count >= NURSERY_CFG.WASTE_MAX then
          if forceDev then
            self.data.devPoopQueued = false
            if active then active.devPoopQueued = false end
          end
          return false
        end

        if forceDev then
          -- Older development saves can enter the exact natural animation path on
          -- the next Nursery visit rather than materializing a pile directly.
          self.data.digestion = math.max(1, tonumber(self.data.digestion) or 0)
          self.data.poopDueAt = nil
          self.data.devPoopQueued = false
          active.devPoopQueued = false
        elseif (tonumber(self.data.digestion) or 0) < 1 then
          return false
        end

        self.pooping = {
          index = 1,
          changedAt = nowSeconds(),
          walkIndex = self.babyWalkIndex,
        }
        self:showThought("angry")
        return true
      end

      function state:spawnPoop()
        local count = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
          math.floor(tonumber(self.data.wasteCount) or 0)))
        if count >= NURSERY_CFG.WASTE_MAX then return false end

        local beforeClean = clampMeter(self.data.clean)
        self.data.clean = clampMeter(beforeClean - 1)
        self.data.wastePenalty = math.max(0, tonumber(self.data.wastePenalty) or 0)
          + (beforeClean - self.data.clean)
        self.data.wasteCount = count + 1
        self.data.wastePresent = true
        self.data.zeldaCareTipsSeen = self.data.zeldaCareTipsSeen or {}
        if self.data.zeldaPendingTip == nil and not self.data.zeldaCareTipsSeen.poop then
          self.data.zeldaPendingTip = "poop"
        end
        self.data.digestion = math.max(0, (tonumber(self.data.digestion) or 0) - 1)
        self.data.poopDueAt = nil
        self.data.poopPendingWake = false

        -- Use OCTAZOOKA's actual Gen II move-sound mapping. The battle engine
        -- already exposes that mapping on the move definition, so this stays
        -- faithful even if the underlying SFX label differs between engines.
        local move = self.game and self.game.data and self.game.data.moves
          and self.game.data.moves.OCTAZOOKA
        if move and move.anim and Sound.playMove then
          Sound.playMove(self.game.data, move.anim)
        else
          -- Crystal's extracted SFX list does not expose an "Sfx_Octazooka"
          -- label directly; Sludge Bomb is only a defensive fallback.
          Sound.play(self.game.data, "Sfx_SludgeBomb")
        end

        self:syncActiveSlot()
        self:schedulePoopIfReady(wallNow())
        return true
      end

      function state:updatePooping()
        local poop = self.pooping
        if not poop then return end
        local now = nowSeconds()
        local elapsed = now - poop.changedAt
        if elapsed < NURSERY_CFG.POOP_STEP_SECONDS then return end
        local whole = math.floor(elapsed / NURSERY_CFG.POOP_STEP_SECONDS)
        poop.index = poop.index + whole
        poop.changedAt = poop.changedAt + whole * NURSERY_CFG.POOP_STEP_SECONDS
        if poop.index > #NURSERY_CFG.POOP_SHAKE then
          self:spawnPoop()
          self.pooping = nil
          self.babyWalkChangedAt = nowSeconds()
        end
      end

      function state:maybeStartPooping()
        if self.data.carePaused == true then return false end
        if self.pooping or self.cleaning or self.eating or self.medicating or self.refusing
            or self.playGame or self.playMenu or self.foodMenu or self.medicineMenu or self.careMenu then
          return false
        end
        local active = self:activeSlotRecord()
        if not (active and active.kind == "baby") then return false end
        if self:isSleeping() then
          if self.data.devPoopQueued == true or active.devPoopQueued == true
              or tonumber(self.data.poopDueAt) ~= nil
              or (tonumber(self.data.digestion) or 0) >= 1 then
            self.data.poopPendingWake = true
            self.data.poopDueAt = nil
          end
          return false
        end
        if self.data.devPoopQueued == true or active.devPoopQueued == true then
          return self:startPooping(true)
        end
        if self.data.poopPendingWake == true then self:schedulePoopIfReady(wallNow()) end
        local due = tonumber(self.data.poopDueAt)
        if due and due <= wallNow() then return self:startPooping(false) end
        return false
      end

      function state:startCleaning()
        if (tonumber(self.data.wasteCount) or 0) <= 0 then
          self:startNoRefusal()
          return
        end
        self.cleaning = {
          index = 1,
          changedAt = nowSeconds(),
          cleared = false,
        }
        -- Water Gun gives the short watery sweep/flush cue without taking over
        -- the nursery music. The visual itself advances in chunky hard steps.
        Sound.play(self.game.data, "Sfx_WaterGun")
      end

      function state:clearWasteFromCleaning()
        local clean = self.cleaning
        if not clean or clean.cleared then return end
        clean.cleared = true
        -- FLUSH is the full reset action for Nursery messes: once the player
        -- cleans up the room, CLEAN is restored all the way back to full.
        self.data.wastePresent = false
        self.data.wasteCount = 0
        self.data.wasteExposure = 0
        self.data.wastePenalty = 0
        self.data.clean = 4
        self.data.devPoopQueued = false

        local slot = self:activeSlotRecord()
        if slot and slot.kind == "baby" then
          -- Clear the persistent resident copy at the exact sweep frame that
          -- clears the room, rather than waiting for the animation's final
          -- sync. This keeps older queued waste state compatible.
          slot.wastePresent = false
          slot.wasteCount = 0
          slot.wasteExposure = 0
          slot.wastePenalty = 0
          slot.clean = 4
          slot.devPoopQueued = false
          applyFriendshipDelta(self.data, slot, NURSERY_CFG.CARE_ACTION_FRIENDSHIP)
        end

        if self.data.zeldaPendingTip == "poop" then self.data.zeldaPendingTip = nil end
        self:schedulePoopIfReady(wallNow())
      end

      function state:updateCleaning()
        local clean = self.cleaning
        if not clean then return end
        local now = nowSeconds()
        local elapsed = now - clean.changedAt
        if elapsed < NURSERY_CFG.CLEAN_STEP_SECONDS then return end
        local whole = math.floor(elapsed / NURSERY_CFG.CLEAN_STEP_SECONDS)
        local oldIndex = clean.index
        clean.index = clean.index + whole
        clean.changedAt = clean.changedAt + whole * NURSERY_CFG.CLEAN_STEP_SECONDS

        local last = math.min(clean.index, #NURSERY_CFG.FLUSH_SWEEP)
        for idx = oldIndex + 1, last do
          if NURSERY_CFG.FLUSH_SWEEP[idx].clearsWaste then
            self:clearWasteFromCleaning()
          end
        end

        if clean.index > #NURSERY_CFG.FLUSH_SWEEP then
          self:clearWasteFromCleaning()
          self.cleaning = nil
          if not self:isSleeping() then self.babyWalkIndex = randomBabyWalkIndex() end
          self.babyWalkChangedAt = nowSeconds()
          self:syncActiveSlot()
          self:setTemporaryCondition("FRESH", "happy", 45)
        end
      end

      function state:updateWasteAnimation()
        if (tonumber(self.data.wasteCount) or 0) <= 0 or self.cleaning then return end
        local now = nowSeconds()
        local elapsed = now - self.wasteChangedAt
        if elapsed >= NURSERY_CFG.WASTE_STEP_SECONDS then
          local whole = math.floor(elapsed / NURSERY_CFG.WASTE_STEP_SECONDS)
          self.wasteFrame = ((self.wasteFrame - 1 + whole) % 2) + 1
          self.wasteChangedAt = self.wasteChangedAt + whole * NURSERY_CFG.WASTE_STEP_SECONDS
        end
      end

      function state:openFoodMenu()
        if self:isSleeping() then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        -- Always let the player inspect what food is currently available.
        -- A full babymon only refuses after a specific food is selected.
        Sound.play(self.game.data, "Sfx_Menu")
        self.foodMenu = {
          rows = ownedFoods(self.game),
          cursor = 1,
          offset = 1,
        }
      end

      function state:startEating(food)
        if not food then return end
        Bag.remove(self.game.save, food.id, 1)
        self.foodMenu = nil
        local sequence = food.anim ~= nil and NURSERY_CFG.BERRY_EAT or NURSERY_CFG.GENERIC_EAT
        self.eating = {
          food = food,
          index = 1,
          changedAt = nowSeconds(),
          sequence = sequence,
          -- Keep the chew audio locked to visible eating changes.  For the
          -- authored Berry sequence the bite plays precisely when the prop
          -- advances FULL -> PARTLY -> MOSTLY -> GONE (steps 3, 5 and 7).
          -- Generic foods do not have prop art yet, so their three bites stay
          -- attached to the visible eating-pose changes until their artwork
          -- arrives.
          biteMarks = food.anim ~= nil
            and { [3] = true, [5] = true, [7] = true }
            or  { [2] = true, [3] = true, [4] = true },
          bitePlayed = {},
        }
      end

      function state:finishEating()
        local food = self.eating and self.eating.food
        if food then
          -- Settle any real elapsed care time before applying the meal, then
          -- restart Hunger's decay interval from the feed itself.  This avoids
          -- a berry being eaten one minute before an old three-hour boundary
          -- and immediately losing the half-heart it just restored.
          local now = wallNow()
          advanceCareClock(self.data, now, true, self.game)
          self.data.hunger = clampMeter(self.data.hunger + (food.hunger or 0))

          -- Meals are the main digestion driver. Lighter foods add ~20%, while
          -- dense treats can add up to 35%. Crossing 100% does not poop
          -- instantly; it starts a random 1-5 minute anticipation timer.
          local wasteCount = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
            math.floor(tonumber(self.data.wasteCount) or 0)))
          self.data.digestion = math.max(0, tonumber(self.data.digestion) or 0)
            + math.max(0, tonumber(food.digestion) or 0)
          self.data.dietStrain = math.max(0, tonumber(self.data.dietStrain) or 0)
            + (FOOD_DIET_STRAIN[food.id] or 0)
          if not self.data.sickness and self.data.dietStrain >= 1 then
            startSickness(self.data, "tummyache")
            self.data.dietStrain = math.max(0, self.data.dietStrain - 1)
          end
          if wasteCount >= NURSERY_CFG.WASTE_MAX then
            self.data.digestion = math.min(self.data.digestion, 1)
            self.data.poopDueAt = nil
            self.data.poopPendingWake = false
          else
            self:schedulePoopIfReady(now)
          end

          self.data.careRemainder = self.data.careRemainder or {}
          self.data.careRemainder.hunger = 0
          self.data.careLastRealAt = now
          self.careClockPolledAt = now
          local slot = self:activeSlotRecord()
          local favoriteFood = false
          if slot and slot.kind == "baby" then
            slot.weightTenths = math.max(1, math.floor(tonumber(slot.weightTenths) or 130)
              + (NURSERY_CFG.FOOD_WEIGHT_TENTHS[food.id] or 0))
            local profile = NURSERY_CFG.PERSONALITY_PROFILES[slot.species]
            favoriteFood = profile ~= nil and profile.favoriteFood == food.id
            local friendshipGain = NURSERY_CFG.CARE_ACTION_FRIENDSHIP
            if favoriteFood then
              slot.preferencesDiscovered = slot.preferencesDiscovered or {}
              slot.preferencesDiscovered.favoriteFood = true
              friendshipGain = friendshipGain + NURSERY_CFG.PREFERENCE_FRIENDSHIP_BONUS
            end
            applyFriendshipDelta(self.data, slot, friendshipGain)
          end
          self:syncActiveSlot()
          self.eatingFavoriteFood = favoriteFood
        end
        self.eating = nil
        self.babyWalkIndex = 1
        self.babyWalkChangedAt = nowSeconds()
        if self.eatingFavoriteFood then
          self:setTemporaryCondition("LOVED", "ecstatic", 60)
        else
          self:setTemporaryCondition("RELAXED", "relaxed", 45)
        end
        self.eatingFavoriteFood = nil
      end

      function state:updateFoodMenu(input)
        local menu = self.foodMenu
        if not menu then return end
        local count = #menu.rows

        if input:wasPressed("b") then
          self.foodMenu = nil
          return
        end
        if count == 0 then
          if input:wasPressed("a") then self.foodMenu = nil end
          return
        end

        if input:wasPressed("up") then
          menu.cursor = menu.cursor - 1
          if menu.cursor < 1 then menu.cursor = count end
        elseif input:wasPressed("down") then
          menu.cursor = menu.cursor + 1
          if menu.cursor > count then menu.cursor = 1 end
        elseif input:wasPressed("a") then
          local slot = self:activeSlotRecord()
          if slot and slot.sickness and slot.sickness.kind == "tummyache" then
            self:startRefusingFood()
          elseif clampMeter(self.data.hunger) >= 4 then
            -- Let the chooser remain useful at full Hunger. Only after the
            -- player actually picks a food does the babymon center itself,
            -- reject the meal with the wrong/error beep, and do its three
            -- back-and-forth "no" turns. No inventory is consumed.
            self:startRefusingFood()
          else
            local food = menu.rows[menu.cursor]
            local profile = slot and NURSERY_CFG.PERSONALITY_PROFILES[slot.species] or nil
            if profile and food and profile.dislikedFood == food.id then
              slot.preferencesDiscovered = slot.preferencesDiscovered or {}
              slot.preferencesDiscovered.dislikedFood = true
              self:startRefusingFood()
            else
              self:startEating(food)
            end
          end
          return
        end

        if menu.cursor < menu.offset then menu.offset = menu.cursor end
        if menu.cursor > menu.offset + 2 then menu.offset = menu.cursor - 2 end
        local maxOffset = math.max(1, count - 2)
        if menu.offset > maxOffset then menu.offset = maxOffset end
      end

      function state:openMedicineMenu()
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if self:isSleeping() then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if not slot.sickness then
          self:startNoRefusal()
          return
        end
        self.medicineMenu = {
          rows = ownedMedicines(self.game),
          cursor = 1,
          offset = 1,
        }
      end

      function state:updateMedicineMenu(input)
        local menu = self.medicineMenu
        if not menu then return end
        local count = #menu.rows
        if input:wasPressed("b") then
          self.medicineMenu = nil
          return
        end
        if count == 0 then
          if input:wasPressed("a") then self.medicineMenu = nil end
          return
        end
        if input:wasPressed("up") then
          menu.cursor = menu.cursor - 1
          if menu.cursor < 1 then menu.cursor = count end
        elseif input:wasPressed("down") then
          menu.cursor = menu.cursor + 1
          if menu.cursor > count then menu.cursor = 1 end
        elseif input:wasPressed("a") then
          self:startMedicating(menu.rows[menu.cursor])
          return
        end
        if menu.cursor < menu.offset then menu.offset = menu.cursor end
        if menu.cursor > menu.offset + 2 then menu.offset = menu.cursor - 2 end
        local maxOffset = math.max(1, count - 2)
        if menu.offset > maxOffset then menu.offset = maxOffset end
      end

      function state:startMedicating(medicine)
        if not medicine then return end
        Bag.remove(self.game.save, medicine.id, 1)
        self.medicineMenu = nil
        self.medicating = {
          medicine = medicine,
          index = 1,
          changedAt = nowSeconds(),
          sequence = NURSERY_CFG.GENERIC_EAT,
          -- Pulse the same medicine-use cue three times over the visible item
          -- animation: once immediately, then again on steps 2 and 3.
          sfxMarks = { [2] = true, [3] = true },
          sfxPlayed = {},
        }
        Sound.play(self.game.data, "Sfx_Menu")
      end

      function state:finishMedicating()
        local med = self.medicating and self.medicating.medicine
        if med then
          local slot = self:activeSlotRecord()
          local sickness = slot and slot.sickness
          if sickness then
            sickness.totalDoses = math.max(0, tonumber(sickness.totalDoses) or 0) + 1
            local correct = medicineIsCorrect(med.id, sickness.kind)
            if correct then
              sickness.correctDoses = math.max(0, tonumber(sickness.correctDoses) or 0) + 1
              self:showThought("happy")
            end
            local cured = (tonumber(sickness.correctDoses) or 0) >= (tonumber(sickness.severity) or 1)
              or (tonumber(sickness.totalDoses) or 0) >= 3
            if cured then
              self.data.sickness = nil
              self.data.dietStrain = 0
              self.data.sicknessRisk = {
                tummyache = 0, tired = 0, rash = 0, feverish = 0, famished = 0,
              }
              applyFriendshipDelta(self.data, slot, NURSERY_CFG.SICKNESS_CURE_FRIENDSHIP)
              self:setTemporaryCondition("RELAXED", "relaxed", 45)
              Sound.play(self.game.data, "Sfx_Twinkle")
            else
              self.data.sickness = sickness
            end
            self:syncActiveSlot()
          end
        end
        self.medicating = nil
        self.babyWalkIndex = 1
        self.babyWalkChangedAt = nowSeconds()
      end

      function state:updateMedicating()
        if not self.medicating then return end
        local med = self.medicating
        local now = nowSeconds()
        local elapsed = now - med.changedAt
        if elapsed < NURSERY_CFG.EAT_STEP_SECONDS then return end
        local whole = math.floor(elapsed / NURSERY_CFG.EAT_STEP_SECONDS)
        local oldIndex = med.index
        med.index = med.index + whole
        med.changedAt = med.changedAt + whole * NURSERY_CFG.EAT_STEP_SECONDS

        -- Service every crossed animation marker so a frame hitch cannot skip
        -- one of the three intended medicine-use sounds.
        local last = math.min(med.index, #med.sequence)
        for idx = oldIndex + 1, last do
          if med.sfxMarks and med.sfxMarks[idx] and not med.sfxPlayed[idx] then
            Sound.play(self.game.data, "Sfx_Menu")
            med.sfxPlayed[idx] = true
          end
        end

        if med.index > #med.sequence then
          self:finishMedicating()
        end
      end

      function state:openPlayMenu()
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if self:isSleeping() then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if slot.sickness then
          self:startNoRefusal()
          return
        end
        -- PLAY is always available for a baby, even at maximum Fun. Unlike
        -- FOOD, play is a recreational interaction rather than a need-only
        -- refill action, so a full Fun meter should never cause refusal.
        Sound.play(self.game.data, "Sfx_Menu")
        self.playMenu = { cursor = 1 }
      end

      function state:updatePlayMenu(input)
        local menu = self.playMenu
        if not menu then return end
        local count = #NURSERY_CFG.PLAY_MENU_ITEMS
        if input:wasPressed("b") then self.playMenu = nil return end
        if input:wasPressed("up") then
          menu.cursor = menu.cursor - 1
          if menu.cursor < 1 then menu.cursor = count end
        elseif input:wasPressed("down") then
          menu.cursor = menu.cursor + 1
          if menu.cursor > count then menu.cursor = 1 end
        elseif input:wasPressed("a") then
          local item = NURSERY_CFG.PLAY_MENU_ITEMS[menu.cursor]
          self:startPlayGame(item)
        end
      end

      function state:playRandomIndex(maximum)
        if love.math and love.math.random then return love.math.random(maximum) end
        return math.random(maximum)
      end

      function state:playRandomUnit()
        if love.math and love.math.random then return love.math.random() end
        return math.random()
      end

      function state:beginMatchWait(pg, now)
        pg.phase = "waiting"
        pg.raised = nil
        pg.facing = nil
        pg.chordFirst = nil
        pg.chordUntil = nil
        pg.nextAt = now + NURSERY_CFG.PLAY_MATCH_WAIT_MIN_SECONDS
          + self:playRandomUnit() * NURSERY_CFG.PLAY_MATCH_WAIT_RANDOM_SECONDS
      end

      function state:beginMemoryRound(pg, now)
        local length = NURSERY_CFG.PLAY_MEMORY_LENGTHS[pg.round] or 2
        pg.sequence = {}
        for i = 1, length do
          pg.sequence[i] = NURSERY_CFG.PLAY_DIRECTIONS[self:playRandomIndex(#NURSERY_CFG.PLAY_DIRECTIONS)]
        end
        pg.inputIndex = 1
        pg.inputFlash = nil
        pg.inputFlashUntil = nil
        -- Reveal the memory sequence progressively: one new arrow every
        -- 0.75 seconds, then leave the completed sequence visible for a full
        -- second before asking the player to reproduce it.
        pg.phase = "reveal"
        pg.revealCount = 1
        pg.revealNextAt = now + NURSERY_CFG.PLAY_MEMORY_STEP_SECONDS
        pg.phaseUntil = nil
        Sound.play(self.game.data, "Sfx_Twinkle")
      end

      function state:startPlayGame(kind)
        local now = nowSeconds()
        local pg = {
          kind = kind,
          phase = "active",
          startedAt = now,
          lastAt = now,
          result = nil,
          -- Friendship from PLAY is care, not an infinite minigame grind.
          -- Snapshot FUN when the game begins so a win only earns Friendship
          -- if the baby actually needed entertainment at the start. Players
          -- can still replay games at full FUN for fun / preference discovery.
          funAtStart = clampMeter(self.data.fun),
        }
        pg.misses = 0
        if kind == "BOUNCE" then
          pg.phase = "falling"
          pg.round = 1
          pg.babyLane = 2
          pg.ballLane = self:playRandomIndex(3)
          pg.ballY = NURSERY_CFG.PLAY_BALL_TOP_Y
          pg.bounces = 0
          pg.dropAt = now + NURSERY_CFG.PLAY_BOUNCE_START_DELAY
          pg.jumpUntil = 0
        elseif kind == "MATCH" then
          pg.round = 1
          pg.hits = 0
          self:beginMatchWait(pg, now)
        elseif kind == "MEMORY" then
          pg.round = 1
          self:beginMemoryRound(pg, now)
        else
          return
        end
        self.playMenu = nil
        self.playGame = pg
        Music.play(self.game.data, "Music_MtMoonSquare", true, { reason = "direct" })
      end

      function state:finishPlayGame(won)
        local pg = self.playGame
        if not pg or pg.result ~= nil then return end
        local perfect = won == true and (tonumber(pg.misses) or 0) == 0
        pg.perfect = perfect
        pg.result = won == true and "win" or "lose"
        pg.phase = "result"
        pg.resultUntil = nowSeconds() + NURSERY_CFG.PLAY_RESULT_SECONDS

        if won == true then
          -- A perfect clear restores a full Fun heart. One missed round is
          -- still a clear, but only restores half a heart. Two misses never
          -- reach this path because the second miss ends the game immediately.
          local reward = perfect and NURSERY_CFG.PLAY_FUN_REWARD
            or NURSERY_CFG.PLAY_FUN_REWARD_IMPERFECT
          local now = wallNow()
          advanceCareClock(self.data, now, true, self.game)
          self.data.fun = clampMeter(self.data.fun + reward)
          self.data.careRemainder = self.data.careRemainder or {}
          self.data.careRemainder.fun = 0
          self.data.careLastRealAt = now
          self.careClockPolledAt = now
          local slot = self:activeSlotRecord()
          local favoriteGame = false
          if slot and slot.kind == "baby" then
            NEO.applyPlayWeightLoss(slot)
            NEO.syncNurseryMonMetadata(slot, slot.nurseryMon)

            local profile = NURSERY_CFG.PERSONALITY_PROFILES[slot.species]
            local friendshipEligible = clampMeter(pg.funAtStart) < 4
            favoriteGame = profile and profile.favoriteGame == pg.kind
            slot.playLossStreak = 0

            -- A favorite game is still discoverable even when FUN is already
            -- full, but neither the normal care point nor the favorite bonus
            -- can be farmed unless PLAY was meeting a real FUN need.
            if favoriteGame then
              slot.preferencesDiscovered = slot.preferencesDiscovered or {}
              slot.preferencesDiscovered.favoriteGame = true
            end

            if friendshipEligible then
              local friendshipGain = NURSERY_CFG.CARE_ACTION_FRIENDSHIP
              if favoriteGame then
                friendshipGain = friendshipGain + NURSERY_CFG.PREFERENCE_FRIENDSHIP_BONUS
              end
              applyFriendshipDelta(self.data, slot, friendshipGain)
            end
          end
          self:syncActiveSlot()
          -- Queue the same dedicated win cue for every PLAY game. Give the
          -- round-result sound a moment to register, then explicitly clear any
          -- still-busy Gen II SFX channel before starting the 1st-place fanfare.
          -- This prevents MATCH/MEMORY's final input sounds from priority-gating
          -- the celebration away.
          local resultNow = nowSeconds()
          pg.winSfxAt = resultNow + 0.35
          pg.winSfxPlayed = false
          pg.winCryAt = resultNow + 1.10
          pg.winCryPlayed = false
          if favoriteGame then
            self:setTemporaryCondition("LOVED", "ecstatic", 60)
          elseif perfect then
            self:setTemporaryCondition("ENERGETIC", "ecstatic", 45)
          else
            self:setTemporaryCondition("PLAYFUL", "happy", 45)
          end
        else
          Sound.play(self.game.data, "Sfx_Wrong")
          local slot = self:activeSlotRecord()
          if slot and slot.kind == "baby" then
            slot.playLossStreak = math.max(0, math.floor(tonumber(slot.playLossStreak) or 0)) + 1
            if slot.playLossStreak >= 2 then
              self:setTemporaryCondition("ANGRY", "angry", 60)
            else
              self:showThought("sad")
            end
          else
            self:showThought("sad")
          end
        end

        Music.play(self.game.data, "Music_Printer", true, { reason = "direct" })
      end

      function state:recordPlayMiss(pg, missSfx)
        pg.misses = (tonumber(pg.misses) or 0) + 1
        if pg.misses > 1 then
          -- Give BOUNCE its physical ball-miss cue before the shared fail cue.
          if missSfx then Sound.play(self.game.data, missSfx) end
          self:finishPlayGame(false)
          return false
        end
        Sound.play(self.game.data, missSfx or "Sfx_Wrong")
        return true
      end

      function state:cancelPlayGame()
        if not self.playGame then return end
        self.playGame = nil
        self.playMenu = { cursor = 1 }
        Music.play(self.game.data, "Music_Printer", true, { reason = "direct" })
      end

      function state:updateBounceGame(pg, input, now)
        local dt = now - (tonumber(pg.lastAt) or now)
        if dt < 0 then dt = 0 end
        if dt > 0.08 then dt = 0.08 end
        pg.lastAt = now

        if input:wasPressed("left") then
          pg.babyLane = math.max(1, (pg.babyLane or 2) - 1)
          Sound.play(self.game.data, "Sfx_Menu")
        elseif input:wasPressed("right") then
          pg.babyLane = math.min(3, (pg.babyLane or 2) + 1)
          Sound.play(self.game.data, "Sfx_Menu")
        end

        if (input:wasPressed("a") or input:wasPressed("up")) and pg.phase == "falling" then
          pg.jumpUntil = now + NURSERY_CFG.PLAY_BOUNCE_JUMP_SECONDS
          Sound.play(self.game.data, "Sfx_JumpOverLedge")
        end

        if pg.phase == "falling" then
          if now < (tonumber(pg.dropAt) or 0) then return end
          local progress = math.min(9, math.max(0, (tonumber(pg.round) or 1) - 1)) / 9
          local speed = NURSERY_CFG.PLAY_BALL_FALL_SPEED_START
            + (NURSERY_CFG.PLAY_BALL_FALL_SPEED_END - NURSERY_CFG.PLAY_BALL_FALL_SPEED_START) * progress
          pg.ballY = (pg.ballY or NURSERY_CFG.PLAY_BALL_TOP_Y) + speed * dt

          if now < (tonumber(pg.jumpUntil) or 0)
              and pg.babyLane == pg.ballLane
              and pg.ballY >= NURSERY_CFG.PLAY_BALL_HIT_MIN_Y
              and pg.ballY <= NURSERY_CFG.PLAY_BALL_HIT_MAX_Y then
            pg.bounces = (pg.bounces or 0) + 1
            pg.phase = "rising"
            pg.jumpUntil = now + 0.12
            Sound.play(self.game.data, "Sfx_BallBounce")
            return
          end

          if pg.ballY > NURSERY_CFG.PLAY_BALL_MISS_Y then
            if not self:recordPlayMiss(pg, "Sfx_BallPoof") then return end
            if (tonumber(pg.round) or 1) >= 10 then
              self:finishPlayGame(true)
              return
            end
            pg.round = (tonumber(pg.round) or 1) + 1
            pg.ballLane = self:playRandomIndex(3)
            pg.ballY = NURSERY_CFG.PLAY_BALL_TOP_Y
            pg.phase = "falling"
            pg.dropAt = now + NURSERY_CFG.PLAY_BOUNCE_BETWEEN_DELAY
            pg.jumpUntil = 0
          end
        elseif pg.phase == "rising" then
          pg.ballY = (pg.ballY or NURSERY_CFG.PLAY_BALL_TOP_Y)
            - NURSERY_CFG.PLAY_BALL_RISE_SPEED * dt
          if pg.ballY <= NURSERY_CFG.PLAY_BALL_TOP_Y then
            pg.ballY = NURSERY_CFG.PLAY_BALL_TOP_Y
            if (tonumber(pg.round) or 1) >= 10 then
              self:finishPlayGame(true)
            else
              pg.round = (tonumber(pg.round) or 1) + 1
              pg.ballLane = self:playRandomIndex(3)
              pg.phase = "falling"
              pg.dropAt = now + NURSERY_CFG.PLAY_BOUNCE_BETWEEN_DELAY
              pg.jumpUntil = 0
            end
          end
        end
      end

      function state:updateMatchGame(pg, input, now)
        local function advanceRound()
          if (tonumber(pg.round) or 1) >= 5 then
            self:finishPlayGame(true)
          else
            pg.round = (tonumber(pg.round) or 1) + 1
            pg.phase = "reset"
            pg.nextAt = now + NURSERY_CFG.PLAY_MATCH_RESET_SECONDS
          end
        end

        local function scoreMatch()
          pg.hits = (pg.hits or 0) + 1
          Sound.play(self.game.data, "Sfx_Tally")
          pg.raised = nil
          pg.facing = nil
          pg.chordFirst = nil
          pg.chordUntil = nil
          advanceRound()
        end

        local function missMatch()
          pg.raised = nil
          pg.facing = nil
          pg.chordFirst = nil
          pg.chordUntil = nil
          if self:recordPlayMiss(pg) then advanceRound() end
        end

        local function chooseFinalPrompt(exclude)
          local options = { "left", "right", "both" }
          local choices = {}
          for _, option in ipairs(options) do
            if option ~= exclude then choices[#choices + 1] = option end
          end
          return choices[self:playRandomIndex(#choices)]
        end

        local leftPressed = input:wasPressed("left")
        local rightPressed = input:wasPressed("right")

        if pg.phase == "waiting" and now >= (tonumber(pg.nextAt) or now) then
          local canFake = (tonumber(pg.round) or 1) >= 3
          local doFake = canFake and self:playRandomUnit() < 0.40
          if doFake then
            -- On rounds 3-5, only 40% of prompts use the quick 0.25-second
            -- fake-out. This keeps late rounds tense without making every flag
            -- automatically suspicious.
            pg.trickRaised = self:playRandomIndex(2) == 1 and "left" or "right"
            pg.finalRaised = chooseFinalPrompt(pg.trickRaised)
            pg.raised = pg.trickRaised
            pg.facing = pg.trickRaised
            pg.phase = "trick"
            pg.trickUntil = now + NURSERY_CFG.PLAY_MATCH_TRICK_SECONDS
          else
            local options = (tonumber(pg.round) or 1) >= 3 and { "left", "right", "both" } or { "left", "right" }
            pg.raised = options[self:playRandomIndex(#options)]
            pg.facing = pg.raised
            pg.phase = "respond"
            pg.deadline = now + NURSERY_CFG.PLAY_MATCH_RESPONSE_SECONDS
          end
          pg.chordFirst = nil
          pg.chordUntil = nil
          Sound.play(self.game.data, "Sfx_Squeak")
        end

        if pg.phase == "trick" then
          if leftPressed or rightPressed then
            missMatch()
            return
          end
          if now >= (tonumber(pg.trickUntil) or now) then
            pg.raised = pg.finalRaised
            pg.facing = pg.finalRaised
            pg.phase = "respond"
            pg.deadline = now + NURSERY_CFG.PLAY_MATCH_RESPONSE_SECONDS
            pg.chordFirst = nil
            pg.chordUntil = nil
            Sound.play(self.game.data, "Sfx_Squeak")
          end
          return
        end

        if pg.phase == "respond" then
          local leftDown = input.isDown and input:isDown("left") or false
          local rightDown = input.isDown and input:isDown("right") or false

          if pg.raised == "both" then
            if (leftDown and rightDown) or (leftPressed and rightPressed) then
              scoreMatch()
              return
            end
            if leftPressed or rightPressed then
              local chosen = leftPressed and "left" or "right"
              if pg.chordFirst and pg.chordFirst ~= chosen
                  and now <= (tonumber(pg.chordUntil) or 0) then
                scoreMatch()
                return
              end
              pg.chordFirst = chosen
              pg.chordUntil = now + NURSERY_CFG.PLAY_MATCH_CHORD_SECONDS
            end
            if pg.chordFirst and now > (tonumber(pg.chordUntil) or now) then
              missMatch()
              return
            end
          else
            if leftPressed or rightPressed then
              local chosen = leftPressed and "left" or "right"
              if chosen ~= pg.raised then
                missMatch()
                return
              end
              scoreMatch()
              return
            end
          end

          if now > (tonumber(pg.deadline) or now) then
            missMatch()
          end
        elseif pg.phase == "reset" and now >= (tonumber(pg.nextAt) or now) then
          self:beginMatchWait(pg, now)
        end
      end

      function state:updateMemoryGame(pg, input, now)
        if pg.inputFlash and now >= (tonumber(pg.inputFlashUntil) or 0) then
          pg.inputFlash = nil
        end

        if pg.phase == "reveal" then
          if now >= (tonumber(pg.revealNextAt) or math.huge) then
            if (tonumber(pg.revealCount) or 1) < #pg.sequence then
              pg.revealCount = (tonumber(pg.revealCount) or 1) + 1
              Sound.play(self.game.data, "Sfx_Twinkle")
              if pg.revealCount >= #pg.sequence then
                pg.phase = "reveal_linger"
                pg.phaseUntil = now + NURSERY_CFG.PLAY_MEMORY_LINGER_SECONDS
              else
                pg.revealNextAt = now + NURSERY_CFG.PLAY_MEMORY_STEP_SECONDS
              end
            else
              pg.phase = "reveal_linger"
              pg.phaseUntil = now + NURSERY_CFG.PLAY_MEMORY_LINGER_SECONDS
            end
          end
          return
        elseif pg.phase == "reveal_linger" then
          if now >= (tonumber(pg.phaseUntil) or now) then
            pg.phase = "input"
            pg.inputIndex = 1
          end
          return
        elseif pg.phase == "between" then
          if now >= (tonumber(pg.phaseUntil) or now) then
            pg.round = (pg.round or 1) + 1
            self:beginMemoryRound(pg, now)
          end
          return
        end

        if pg.phase ~= "input" then return end
        local chosen = nil
        if input:wasPressed("left") then chosen = "left"
        elseif input:wasPressed("right") then chosen = "right"
        elseif input:wasPressed("up") then chosen = "up"
        elseif input:wasPressed("down") then chosen = "down" end
        if not chosen then return end

        pg.inputFlash = chosen
        pg.inputFlashUntil = now + NURSERY_CFG.PLAY_MEMORY_FLASH_SECONDS
        Sound.play(self.game.data, "Sfx_PushButton")
        if chosen ~= pg.sequence[pg.inputIndex] then
          if not self:recordPlayMiss(pg) then return end
          if (pg.round or 1) >= #NURSERY_CFG.PLAY_MEMORY_LENGTHS then
            self:finishPlayGame(true)
          else
            pg.phase = "between"
            pg.phaseUntil = now + NURSERY_CFG.PLAY_MEMORY_BETWEEN_SECONDS
          end
          return
        end

        pg.inputIndex = pg.inputIndex + 1
        if pg.inputIndex > #pg.sequence then
          -- Positive/negative audio feedback is given at the end of every
          -- MEMORY sequence. Sfx_Tally is the affirmative cue; recordPlayMiss
          -- already supplies Sfx_Wrong for an incorrect sequence.
          Sound.play(self.game.data, "Sfx_Tally")
          if (pg.round or 1) >= #NURSERY_CFG.PLAY_MEMORY_LENGTHS then
            self:finishPlayGame(true)
          else
            pg.phase = "between"
            pg.phaseUntil = now + NURSERY_CFG.PLAY_MEMORY_BETWEEN_SECONDS
          end
        end
      end

      function state:updatePlayGame(input)
        local pg = self.playGame
        if not pg then return end
        local now = nowSeconds()
        if pg.phase == "result" then
          if pg.result == "win" and not pg.winSfxPlayed
              and now >= (tonumber(pg.winSfxAt) or math.huge) then
            pg.winSfxPlayed = true
            -- Gen II's SFX priority gate can discard the fanfare while the
            -- final prompt/tally is still active. Clear that channel first so
            -- MATCH and MEMORY get the exact same audible win cue as BOUNCE.
            if Sound.waitSfxDone then Sound.waitSfxDone() end
            Sound.play(self.game.data, "Sfx_1stPlace")
          end
          if pg.result == "win" and not pg.winCryPlayed
              and now >= (tonumber(pg.winCryAt) or math.huge) then
            pg.winCryPlayed = true
            local slot = self:activeSlotRecord()
            local species = slot and slot.species
            if not (species and Sound.playCry(self.game.data, species)) then
              Sound.play(self.game.data, "Sfx_Twinkle")
            end
          end
          if now >= (tonumber(pg.resultUntil) or now) then
            self.playGame = nil
            self.playMenu = { cursor = 1 }
          end
          return
        end
        if input:wasPressed("b") then
          self:cancelPlayGame()
          return
        end
        if pg.kind == "BOUNCE" then self:updateBounceGame(pg, input, now)
        elseif pg.kind == "MATCH" then self:updateMatchGame(pg, input, now)
        elseif pg.kind == "MEMORY" then self:updateMemoryGame(pg, input, now) end
      end

      function state:activate(index)
        local slot = self:activeSlotRecord()
        local eggActive = slot and slot.kind == "egg"

        -- Fresh-player guided onboarding is intentionally single-path:
        -- STATUS -> NEW EGG. Every other bottom icon gives only the ordinary
        -- negative beep and performs no action until Zelda completes her final
        -- explanation and has fully left the Nursery.
        if self:tutorialInputLocked() then
          if self.data.zeldaIntroAwaitingEgg == true and index == 6 then
            self:openCareMenu()
          else
            Sound.play(self.game.data, "Sfx_Wrong")
          end
          return
        end

        if self.data.carePaused == true and index ~= 6 then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if index == 6 then
          self:openCareMenu()
          return
        end

        -- With no resident at all, baby-specific actions are meaningless.
        -- This also prevents CLEAN from drawing a stale/default baby sprite.
        if slot == nil and index >= 1 and index <= 5 then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end

        if eggActive and index ~= 7
          and not (index == 8 and self:zeldaPortraitAvailable()) then
          Sound.play(self.game.data, "Sfx_Wrong")
          return
        end
        if index == 1 then
          self:openFoodMenu()
        elseif index == 2 then
          self:openPlayMenu()
        elseif index == 3 then
          self:startCleaning()
        elseif index == 4 then
          self:openMedicineMenu()
        elseif index == 5 then
          local turningOff = self.data.lightsOn ~= false
          if turningOff and self:sleepWindowActive() and slot and slot.kind == "baby" then
            self.data.sleepWalkIndex = math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
              math.floor(tonumber(self.babyWalkIndex) or 1)))
            slot.sleepWalkIndex = self.data.sleepWalkIndex
            self.movementFlourish = nil
          end
          self.data.lightsOn = not self.data.lightsOn
          self.babyWalkChangedAt = nowSeconds()
          Sound.play(self.game.data, "Sfx_SwitchPockets")
        elseif index == 7 then
          Sound.play(self.game.data, "Sfx_Menu")
          self:openCallMenu()
        elseif index == 8 and self:zeldaPortraitAvailable() then
          Sound.play(self.game.data, "Sfx_Menu")
          if self.data.callPendingContact == "zelda" then
            self:openZeldaProactiveHelp()
          else
            self:openZeldaContextHelp()
          end
        end
        -- Once a baby has hatched, the normal care icons and Zelda help flow are live.
        -- While an Egg is waiting, STATUS and CALL/Zelda help remain available.
      end

      function state:updateEating()
        if not self.eating then return end
        local eat = self.eating
        local now = nowSeconds()
        local elapsed = now - eat.changedAt
        if elapsed < NURSERY_CFG.EAT_STEP_SECONDS then return end
        local whole = math.floor(elapsed / NURSERY_CFG.EAT_STEP_SECONDS)
        local oldIndex = eat.index
        eat.index = eat.index + whole
        eat.changedAt = eat.changedAt + whole * NURSERY_CFG.EAT_STEP_SECONDS

        -- If a frame hitch crosses more than one authored eating step, service
        -- every missed chew marker once rather than silently dropping SFX.
        local last = math.min(eat.index, #eat.sequence)
        for idx = oldIndex + 1, last do
          if eat.biteMarks[idx] and not eat.bitePlayed[idx] then
            Sound.play(self.game.data, "Sfx_Bite")
            eat.bitePlayed[idx] = true
          end
        end

        if eat.index > #eat.sequence then self:finishEating() end
      end

      function state:movementProfile(slot)
        local species = slot and slot.species
        return (species and NURSERY_CFG.MOVEMENT_PROFILES[species]) or NURSERY_CFG.MOVEMENT_DEFAULT
      end

      function state:movementRandom()
        if love.math and love.math.random then return love.math.random() end
        return math.random()
      end

      function state:movementWeightedChoice(profile)
        local choices = {
          { kind = "turn", weight = tonumber(profile.turn) or 0 },
          { kind = "hop", weight = tonumber(profile.hop) or 0 },
          { kind = "back", weight = tonumber(profile.back) or 0 },
          { kind = "cartwheel", weight = tonumber(profile.cartwheel) or 0 },
        }
        local total = 0
        for _, choice in ipairs(choices) do total = total + math.max(0, choice.weight) end
        if total <= 0 then return nil end
        local roll = self:movementRandom() * total
        local acc = 0
        for _, choice in ipairs(choices) do
          acc = acc + math.max(0, choice.weight)
          if roll <= acc then return choice.kind end
        end
        return choices[#choices].kind
      end

      function state:startMovementFlourish(kind)
        local base = NURSERY_CFG.BABY_WALK[math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
          math.floor(tonumber(self.babyWalkIndex) or 1)))]
        if not base then return end
        local x, y, flip = base.x or 52, base.y or 52, base.flip == true
        local steps, seconds
        if kind == "turn" then
          seconds = NURSERY_CFG.MOVEMENT_TURN_SECONDS
          steps = {
            { frame = 1, x = x, y = y, flip = flip },
            { frame = 2, x = x, y = y, flip = not flip },
            { frame = 1, x = x, y = y, flip = flip },
            { frame = 2, x = x, y = y, flip = not flip },
            { frame = 1, x = x, y = y, flip = flip },
          }
        elseif kind == "hop" then
          seconds = NURSERY_CFG.MOVEMENT_HOP_SECONDS
          steps = {
            { frame = 1, x = x, y = y,     flip = flip },
            { frame = 2, x = x, y = y - 4, flip = flip },
            { frame = 1, x = x, y = y - 9, flip = flip },
            { frame = 2, x = x, y = y - 4, flip = flip },
            { frame = 1, x = x, y = y,     flip = flip },
          }
        elseif kind == "back" then
          seconds = NURSERY_CFG.MOVEMENT_BACK_SECONDS
          steps = {
            { frame = 1, x = x, y = y, flip = flip },
            { frame = 1, x = x, y = y, flip = flip, back = true },
            { frame = 2, x = x, y = y, flip = not flip, back = true },
            { frame = 1, x = x, y = y, flip = not flip },
            { frame = 1, x = x, y = y, flip = flip },
          }
        elseif kind == "cartwheel" then
          seconds = NURSERY_CFG.MOVEMENT_CARTWHEEL_SECONDS
          local dir = flip and -1 or 1
          steps = {
            { frame = 1, x = x,         y = y,     flip = flip, rotation =   0 },
            { frame = 2, x = x + 3*dir, y = y - 2, flip = flip, rotation =  90*dir },
            { frame = 1, x = x + 6*dir, y = y - 3, flip = flip, rotation = 180*dir },
            { frame = 2, x = x + 3*dir, y = y - 2, flip = flip, rotation = 270*dir },
            { frame = 1, x = x,         y = y,     flip = flip, rotation = 360*dir },
          }
        elseif kind == "crystal_special" then
          local slot = self:activeSlotRecord()
          local sequence = slot and NURSERY_CFG.NEO.officialFlourishFrames[slot.species]
          if sequence and slot.spriteStyle == "crystal" then
            seconds = 0.18
            steps = {}
            for _, actionFrame in ipairs(sequence) do
              steps[#steps + 1] = {
                frame = 1, actionFrame = actionFrame,
                x = x, y = y, flip = flip,
              }
            end
          end
        end
        if not (steps and #steps > 0) then return end
        self.movementFlourish = { kind = kind, steps = steps, index = 1, changedAt = nowSeconds(), seconds = seconds }

        local slot = self:activeSlotRecord()
        local healthy = slot and slot.kind == "baby" and not slot.sickness
          and clampMeter(self.data.hunger) > 1
          and clampMeter(self.data.fun) > 1
          and clampMeter(self.data.clean) > 1
        if healthy then
          if kind == "cartwheel" then
            self:setTemporaryCondition("GRACEFUL", "happy", 20)
          elseif kind == "hop" or kind == "crystal_special" then
            self:setTemporaryCondition("ENERGETIC", "ecstatic", 20)
          elseif kind == "back" then
            self:setTemporaryCondition("CURIOUS", "curious", 20)
          elseif kind == "turn" and self:movementRandom() < 0.30 then
            self:setTemporaryCondition("DAYDREAMING", "relaxed", 20)
          end
        end
      end

      function state:currentMovementStep()
        if self.data.carePaused == true and type(self.data.pausedBabyStep) == "table" then
          return self.data.pausedBabyStep
        end
        local flourish = self.movementFlourish
        if flourish and flourish.steps then
          return flourish.steps[math.max(1, math.min(#flourish.steps, math.floor(tonumber(flourish.index) or 1)))]
        end
        return NURSERY_CFG.BABY_WALK[math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
          math.floor(tonumber(self.babyWalkIndex) or 1)))]
      end

      function state:updateWander()
        if self.data.carePaused == true or self:isSleeping() then return end
        local now = nowSeconds()
        local slot = self:activeSlotRecord()

        -- Once an idle flourish begins, service every hard animation step before
        -- returning to normal walking. Sick babies skip playful flourishes.
        local flourish = self.movementFlourish
        if flourish then
          local seconds = math.max(0.05, tonumber(flourish.seconds) or 0.2)
          local elapsed = now - (tonumber(flourish.changedAt) or now)
          if elapsed >= seconds then
            local whole = math.floor(elapsed / seconds)
            flourish.index = (tonumber(flourish.index) or 1) + whole
            flourish.changedAt = (tonumber(flourish.changedAt) or now) + whole * seconds
            if flourish.index > #flourish.steps then
              self.movementFlourish = nil
              self.babyWalkChangedAt = now
            end
          end
          return
        end

        local elapsed = now - self.babyWalkChangedAt
        local profile = self:movementProfile(slot)
        local stepSeconds = NURSERY_CFG.BABY_STEP_SECONDS
          * math.max(0.55, tonumber(profile.stepScale) or 1)
          * NEO.weightMovementScale(slot)
        if slot and slot.sickness then stepSeconds = stepSeconds * 1.75 end
        if elapsed >= stepSeconds then
          local wholeSteps = math.floor(elapsed / stepSeconds)
          self.babyWalkIndex = ((self.babyWalkIndex - 1 + wholeSteps) % #NURSERY_CFG.BABY_WALK) + 1
          self.babyWalkChangedAt = self.babyWalkChangedAt + wholeSteps * stepSeconds

          if not (slot and slot.sickness) then
            local chance = math.max(0, math.min(0.15, tonumber(profile.flourishChance) or 0))
            if self:movementRandom() < chance then
              local kind
              local crystalSequence = slot and slot.spriteStyle == "crystal"
                and NURSERY_CFG.NEO.officialFlourishFrames[slot.species] or nil
              -- About one third of already-rare flourishes use the native
              -- Crystal animation pose; normal turn/hop/back/cartwheel behavior
              -- still supplies most movement variety.
              if crystalSequence and self:movementRandom() < 0.34 then
                kind = "crystal_special"
              else
                kind = self:movementWeightedChoice(profile)
              end
              if kind then self:startMovementFlourish(kind) end
            end
          end
        end
      end

      function state:exit()
        if self:isSleeping() then
          self.data.sleepWalkIndex = math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
            math.floor(tonumber(self.babyWalkIndex) or 1)))
        end
        if self.data.carePaused == true then
          self.data.pausedBabyWalkIndex = math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
            math.floor(tonumber(self.babyWalkIndex) or 1)))
        end
        self:syncActiveSlot()
        -- StateStack calls exit() for normal B exits, stack clears and launcher
        -- transitions, so the map/previous theme is never left replaced.
        if self.previousMusic then
          Music.play(self.game.data, self.previousMusic, true, { reason = "direct" })
        else
          Music.restoreMap(self.game.data, "babycare_exit")
        end
      end

      function state:update()
        updateRoomRotation(self.data)
        self:updateAges()
        self:updateEggs()
        if (tonumber(self.pendingHappinessElapsed) or 0) > 0 then
          self:updateHappiness(self.pendingHappinessElapsed)
          self.pendingHappinessElapsed = 0
          self:syncActiveSlot()
        end

        -- Keep every occupied Nursery slot on its own real-world care clock.
        -- The selected baby still receives live thought feedback; inactive
        -- residents advance silently and are already current when selected.
        self:updateThought()
        local careNow = wallNow()
        if careNow ~= self.careClockPolledAt then
          local active = self:activeSlotRecord()
          local oldHunger = clampMeter(self.data.hunger)
          local oldFun = clampMeter(self.data.fun)
          local oldClean = clampMeter(self.data.clean)
          local elapsed = advanceAllResidentCare(self.data, careNow, self.game, true)
          self:updateHappiness(elapsed)
          if active and active.kind == "baby" and not self.thoughtBubble then
            if oldHunger > 0 and clampMeter(self.data.hunger) == 0 then
              self:showThought("famished")
            elseif oldFun > 0 and clampMeter(self.data.fun) == 0 then
              self:showThought("sad")
            elseif oldClean > 0 and clampMeter(self.data.clean) == 0 then
              self:showThought("miserable")
            end
          end
          self.careClockPolledAt = careNow
        end

        self:rollAmbientCondition(false)
        self:updateZeldaSlide()

        local input = game.input
        if not input then return end

        if self.playGame then
          self:updatePlayGame(input)
          return
        end

        if self.playMenu then
          self:updatePlayMenu(input)
          return
        end

        if self.eating then
          self:updateEating()
          return
        end

        if self.medicating then
          self:updateMedicating()
          return
        end

        if self.refusing then
          self:updateRefusingFood()
          return
        end

        if self.cleaning then
          self:updateCleaning()
          return
        end

        if self.pooping then
          self:updatePooping()
          return
        end

        if self.foodMenu then
          self:updateFoodMenu(input)
          return
        end

        if self.medicineMenu then
          self:updateMedicineMenu(input)
          return
        end

        if self.careMenu then
          self:updateCareMenu(input)
          return
        end

        if self.callMenu then
          self:updateCallMenu(input)
          return
        end

        local active = self:activeSlotRecord()
        if active and active.kind == "baby" then
          if self:maybeStartPooping() then
            self:updatePooping()
            return
          end
          self:updateWander()
          self:updateWasteAnimation()
        end

        if self.data.carePaused == true then
          -- PAUSE CARE freezes the Nursery and locks the bottom bar to CARE,
          -- where STATUS / RESUME CARE remain available.
          self.cursor = 6
          if input:wasPressed("a") then
            self:openCareMenu()
          elseif input:wasPressed("b") then
            self:syncActiveSlot()
            game.stack:pop()
          end
          return
        end

        local bottomCount = self:zeldaPortraitAvailable() and #NURSERY_CFG.SELECTOR_POS or (#NURSERY_CFG.SELECTOR_POS - 1)
        if self.cursor > bottomCount then self.cursor = bottomCount end
        if input:wasPressed("left") then
          self.cursor = self.cursor - 1
          if self.cursor < 1 then self.cursor = bottomCount end
        elseif input:wasPressed("right") then
          self.cursor = self.cursor + 1
          if self.cursor > bottomCount then self.cursor = 1 end
        elseif input:wasPressed("a") then
          self:activate(self.cursor)
        elseif input:wasPressed("b") then
          if self:tutorialInputLocked() then
            Sound.play(self.game.data, "Sfx_Wrong")
          else
            self:syncActiveSlot()
            game.stack:pop()
          end
        end
      end

      function state:drawMedicineMenu()
        local menu = self.medicineMenu
        if not menu then return end
        local G = love.graphics
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", 0, 30, 160, 85)
        G.setColor(0, 0, 0, 1)
        Chrome.textbox(0, 4, 18, 8)
        Font.draw("WHICH MED?", 9, 40)

        if #menu.rows == 0 then
          local empty = "NO MED ITEMS."
          Font.draw(empty, math.floor((160 - Font.width(empty)) / 2), 72)
          return
        end

        local first = menu.offset
        local last = math.min(#menu.rows, first + 2)
        for rowIndex = first, last do
          local visual = rowIndex - first
          local y = 56 + visual * 16
          local row = menu.rows[rowIndex]
          if rowIndex == menu.cursor then drawMenuCursor(9, y) end
          Font.draw(row.label, 19, y)
          local qty = "x" .. tostring(row.count)
          Font.draw(qty, 146 - Font.width(qty), y)
        end

        if first > 1 then drawNativeScrollUp() end
        if last < #menu.rows then drawNativeScrollDown() end
      end

      function state:drawFoodMenu()
        local menu = self.foodMenu
        if not menu then return end
        local G = love.graphics

        -- Blank the complete middle band first, then use Crystal's actual
        -- shared Gen 2 menu chrome for the chooser instead of the prototype's
        -- hand-drawn black rectangle.  This is the same border glyph set used
        -- by vanilla in-game menus/text boxes, matching the supplied mockup.
        -- HUD ends at y=29; bottom command art resumes at y=115.
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", 0, 30, 160, 85)
        G.setColor(0, 0, 0, 1)
        Chrome.textbox(0, 4, 18, 8)

        -- The vanilla border occupies the entire top/bottom tile rows. Keep
        -- all copy inside the interior instead of letting the old prototype
        -- coordinates ride over the frame.  The title now starts on the first
        -- interior row and the three visible food rows use Crystal-like 16px
        -- vertical spacing, matching the supplied menu mockup.
        Font.draw("WHICH FOOD?", 9, 40)

        if #menu.rows == 0 then
          local empty = "NO FOOD ITEMS."
          Font.draw(empty, math.floor((160 - Font.width(empty)) / 2), 72)
          return
        end

        local first = menu.offset
        local last = math.min(#menu.rows, first + 2)
        for rowIndex = first, last do
          local visual = rowIndex - first
          local y = 56 + visual * 16
          local row = menu.rows[rowIndex]
          if rowIndex == menu.cursor then drawMenuCursor(9, y) end
          Font.draw(row.label, 19, y)
          local qty = "x" .. tostring(row.count)
          Font.draw(qty, 146 - Font.width(qty), y)
        end

        if first > 1 then drawNativeScrollUp() end
        if last < #menu.rows then drawNativeScrollDown() end
      end

      function state:drawCareFrame()
        local G = love.graphics
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", 0, 30, 160, 85)
        G.setColor(0, 0, 0, 1)
        Chrome.textbox(0, 4, 18, 8)
      end

      function state:drawHappinessBar(slot)
        local G = love.graphics
        local x, y, w, h = 8, 98, 144, 8
        local segments = 35
        local cellW, gap = 3, 1
        local value = clampHappiness(slot and slot.happiness or 0)
        local filled = math.floor((value * segments) / 100 + 0.0001)

        -- Match the authored STATUS mockup: a black meter bed with progress
        -- shown as tiny separated rectangular cells rather than one solid bar.
        G.setColor(0, 0, 0, 1)
        G.rectangle("fill", x, y, w, h)
        G.setColor(1, 1, 1, 1)
        for i = 0, filled - 1 do
          local cx = x + 2 + i * (cellW + gap)
          G.rectangle("fill", cx, y + 1, cellW, h - 2)
        end
        G.setColor(1, 1, 1, 1)
      end

      function state:drawCareMain(menu)
        self:drawCareFrame()
        if self.data.carePaused == true then
          local labels = { "STATUS", "RESUME CARE", "CANCEL" }
          local cursor = math.max(1, math.min(#labels, math.floor(tonumber(menu.pauseCursor) or 1)))
          for i, label in ipairs(labels) do
            local y = 40 + (i - 1) * 16
            if i == cursor then Chrome.cursor(1, math.floor(y / 8)) end
            Font.draw(label, 19, y)
          end
          return
        end
        self:keepCareCursorVisible(menu)
        local first = menu.offset or 1
        local last = math.min(#NURSERY_CFG.CARE_ITEMS, first + NURSERY_CFG.CARE_VISIBLE_ROWS - 1)
        for i = first, last do
          local visual = i - first
          local y = 40 + visual * 16
          if i == menu.cursor then Chrome.cursor(1, math.floor(y / 8)) end
          Font.draw(self:careMainLabel(i), 19, y)
        end
        if first > 1 then drawNativeScrollUp() end
        if last < #NURSERY_CFG.CARE_ITEMS then drawNativeScrollDown() end
      end

      function state:drawStatusPage()
        self:drawCareFrame()
        local slot = self:activeSlotRecord()
        if not slot then
          Font.draw("NO BABYMON", 8, 40)
          return
        end
        if slot.kind == "egg" then
          Font.draw("EGG", 8, 40)
          local elapsed = eggElapsedMinutes(slot, self.game)
          local remain = math.max(0, math.ceil(NURSERY_CFG.EGG_HATCH_MINUTES - elapsed))
          if remain > 0 then
            Font.draw("HATCH IN: " .. tostring(remain) .. " MIN", 8, 56)
          else
            Font.draw("READY TO HATCH", 8, 56)
          end
          return
        end

        local name = tostring(slot.nickname or slot.species or "BABY")
        local masteredStyle = OFFICIAL_BABY_SPECIES[slot.species]
          and self.data.friendshipMasteredSpecies and self.data.friendshipMasteredSpecies[slot.species] == true
        local pageMax = masteredStyle and 4 or 3
        local page = self.careMenu and math.max(1, math.min(pageMax,
          math.floor(tonumber(self.careMenu.statusPage) or 1))) or 1

        if page == 1 then
          Font.draw(name, 8, 40)
          local glyph = genderGlyph(slot.gender)
          if glyph ~= "" then Chrome.print(glyph, 18, 5) end
          local age = math.max(0, math.floor(tonumber(slot.ageDays) or 0))
          local wt = math.max(0, math.floor(tonumber(slot.weightTenths) or 0))
          local whole, tenth = math.floor(wt / 10), wt % 10
          local weightText = tenth == 0 and tostring(whole) or (tostring(whole) .. "." .. tostring(tenth))
          Font.draw("AGE:" .. tostring(age) .. "D  LBS:" .. weightText, 8, 56)
          Font.draw("COND: " .. self:currentConditionLabel(slot), 8, 72)
          Font.draw("FRIENDSHIP:", 8, 88)
          drawStatusPageNavHint(108, 88)
          self:drawHappinessBar(slot)
          return
        end

        local profile = NURSERY_CFG.PERSONALITY_PROFILES[slot.species]
        local seen = slot.preferencesDiscovered or {}
        local function foodLabel(id)
          if not id then return "???" end
          for _, def in ipairs(NURSERY_CFG.FOOD_DEFS) do
            if def.id == id then return def.label end
          end
          return tostring(id)
        end

        if page == 2 then
          Font.draw(name .. " LIKES", 8, 40)
          Font.draw("FOOD:", 8, 56)
          Font.draw((profile and seen.favoriteFood) and foodLabel(profile.favoriteFood) or "???", 8, 72)
          Font.draw("GAME: " .. ((profile and seen.favoriteGame) and tostring(profile.favoriteGame) or "???"), 8, 88)
          drawStatusPageNavHint(108, 88)
          return
        end

        if page == 4 and masteredStyle then
          Font.draw(name .. " ART", 8, 40)
          Font.draw("SPRITE STYLE:", 8, 56)
          local style = slot.spriteStyle == "crystal" and "CRYSTAL" or "NEO"
          Font.draw(style, 8, 72)
          Font.draw("A: CHANGE", 8, 88)
          drawStatusPageNavHint(84, 88)
          return
        end

        local function hourText(hour)
          hour = math.floor(tonumber(hour) or 0) % 24
          local suffix = hour >= 12 and "PM" or "AM"
          local h = hour % 12
          if h == 0 then h = 12 end
          return tostring(h) .. suffix
        end
        local startHour = (profile and profile.sleepStart) or NURSERY_CFG.DEFAULT_SLEEP_START_HOUR
        local wakeHour = (profile and profile.sleepWake) or NURSERY_CFG.DEFAULT_SLEEP_END_HOUR
        Font.draw(name .. " ROUTINE", 8, 40)
        Font.draw("DISLIKE:", 8, 56)
        Font.draw((profile and seen.dislikedFood) and foodLabel(profile.dislikedFood) or "???", 8, 72)
        Font.draw("BED: " .. hourText(startHour) .. "-" .. hourText(wakeHour), 8, 88)
        drawStatusPageNavHint(108, 88)
      end

      function state:drawEggPage(menu)
        self:drawCareFrame()
        Font.draw("WHICH EGG?", 8, 40)
        local choices = self:eggChoices()
        if #choices == 0 then choices = { { id = "RANDOM", label = "ODD EGG" } } end
        if menu.eggChoice > #choices then menu.eggChoice = #choices end
        local choice = choices[menu.eggChoice]

        -- The selectors point outward using Crystal's actual filled menu
        -- cursor tile.  The left one is the same native pixel glyph mirrored.
        drawNativeMenuArrow(48, 64, true)
        drawNativeMenuArrow(104, 64, false)

        -- Draw Crystal's actual 5x5 EggPic from the vanilla status page,
        -- centred in the picker rather than anchored from the old icon math.
        local eggX, eggY = eggTopLeftForCenter(self.art, 84, 88, 1)
        local neoEggSpecies = choice and NURSERY_CFG.NEO.species[choice.id] and choice.id or nil
        drawEgg(self.art, self.game, eggX, eggY, 1, neoEggSpecies)
        local label = choice and choice.label or "ODD EGG"
        Font.draw(label, math.floor((160 - Font.width(label)) / 2), 92)

        local open = self:firstOpenSlot()
        if not open then
          local msg = "NO OPEN SLOT"
          Font.draw(msg, math.floor((160 - Font.width(msg)) / 2), 102)
        end
      end

      function state:drawSwitchPage(menu)
        self:drawCareFrame()
        Font.draw("WHICH SLOT?", 8, 40)
        local ys = { 56, 72, 88 }
        for i = 1, NURSERY_CFG.SLOT_COUNT do
          if i == menu.slotCursor then Chrome.cursor(1, math.floor(ys[i] / 8)) end
          Font.draw(tostring(i) .. ".", 19, ys[i])
          local slot = self.data.slots[i]
          Font.draw(slotLabel(slot), 35, ys[i])
          if slot and slot.kind == "baby" then
            local glyph = genderGlyph(slot.gender)
            if glyph ~= "" then Chrome.print(glyph, 18, math.floor(ys[i] / 8)) end
          end
        end
      end

      function state:drawCareMenu()
        local menu = self.careMenu
        if not menu then return end
        if menu.page == "main" then self:drawCareMain(menu)
        elseif menu.page == "status" then self:drawStatusPage()
        elseif menu.page == "egg" then self:drawEggPage(menu)
        elseif menu.page == "switch" then self:drawSwitchPage(menu)
        end
      end

      function state:drawCallMenu()
        local menu = self.callMenu
        if not menu then return end
        self:drawCareFrame()
        Font.draw("CALL", 8, 40)
        local contacts = menu.contacts or NURSERY_CFG.CALL_CONTACTS
        if #contacts == 0 then
          Font.draw("NO CONTACTS", 19, 56)
          return
        end
        for i, contact in ipairs(contacts) do
          local y = 56 + (i - 1) * 16
          if i == menu.cursor then drawMenuCursor(9, y) end
          Font.draw(contact.label or "???", 19, y)
        end
      end

      function state:drawPlayMenu()
        local menu = self.playMenu
        if not menu then return end
        self:drawCareFrame()
        Font.draw("WHICH GAME?", 8, 40)
        for i, label in ipairs(NURSERY_CFG.PLAY_MENU_ITEMS) do
          local y = 56 + (i - 1) * 16
          if i == menu.cursor then Chrome.cursor(1, math.floor(y / 8)) end
          Font.draw(label, 19, y)
        end
      end

      function state:drawPlayBaby(x, y, forceFrame, flip)
        local frame = forceFrame
        if not frame then frame = (math.floor(nowSeconds() * 3) % 2) + 1 end
        self.lastBabyBounds = drawBabyStep(self.art,
          { frame = frame, x = x or 52, y = y or 52, flip = flip == true },
          self:activeSlotRecord(), self.game)
      end

      function state:drawPlayCounter(current, total)
        local text = tostring(current or 0) .. "/" .. tostring(total or 0)
        -- A tiny native Gen II window keeps progress readable against every
        -- Nursery wallpaper without introducing a custom HUD style.
        Chrome.box(0, 4, #text + 2, 3)
        Font.draw(text, 8, 40)
      end

      function state:drawPlayGame()
        local pg = self.playGame
        if not pg then return end
        local now = nowSeconds()
        if pg.phase == "result" then
          self:drawPlayBaby(52, 52, pg.result == "win" and 2 or 1)
          -- MEMORY's final button press used to vanish on the same frame that
          -- the game entered RESULT. Preserve that brief arrow flash here.
          if pg.kind == "MEMORY" and pg.inputFlash
              and now < (tonumber(pg.inputFlashUntil) or 0) then
            local image = self.art.play.arrows[pg.inputFlash]
            if image then drawImage(image, math.floor((160 - 17) / 2), 37) end
          end
          return
        end

        if pg.kind == "BOUNCE" then
          local lane = math.max(1, math.min(3, tonumber(pg.babyLane) or 2))
          local jumpY = now < (tonumber(pg.jumpUntil) or 0) and 44 or 52
          local babyX = NURSERY_CFG.PLAY_BABY_LANES[lane]
          self:drawPlayBaby(babyX, jumpY, now < (tonumber(pg.jumpUntil) or 0) and 2 or nil)
          -- Draw HUD before the ball so a left-lane drop always passes in
          -- front of the progress window rather than disappearing behind it.
          self:drawPlayCounter(pg.round or 1, 10)
          local ballLane = math.max(1, math.min(3, tonumber(pg.ballLane) or 2))
          local ballX = NURSERY_CFG.PLAY_BABY_LANES[ballLane] + 21
          drawImage(self.art.play.ball, ballX, math.floor(tonumber(pg.ballY) or NURSERY_CFG.PLAY_BALL_TOP_Y))
          return
        end

        if pg.kind == "MATCH" then
          local facing = pg.facing or pg.raised
          local facingLeft = facing == "left"
          local facingRight = facing == "right"
          local facingSingle = facingLeft or facingRight
          -- Crystal only gives us the baby's frontpic animation here, not a
          -- dedicated side-view sprite. The supplied pose's natural visual lean
          -- reads toward LEFT, so mirror it for RIGHT and nudge the body toward
          -- the raised flag. BOTH stays front.
          local babyX = facingLeft and 48 or (facingRight and 56 or 52)
          self:drawPlayBaby(babyX, 52, facingSingle and 2 or nil, facingRight)
          local G = love.graphics
          local leftUp = pg.raised == "left" or pg.raised == "both"
          local rightUp = pg.raised == "right" or pg.raised == "both"
          local leftImage = leftUp and self.art.play.flagUp or self.art.play.flagDown
          local rightImage = rightUp and self.art.play.flagUp or self.art.play.flagDown
          G.setColor(1, 1, 1, 1)
          -- Mirror the supplied right-hand flag art for the baby's left side.
          G.draw(leftImage, 47, 67, 0, -1, 1)
          G.draw(rightImage, 113, 67)
          G.setColor(1, 1, 1, 1)
          self:drawPlayCounter(pg.round or 1, 5)
          return
        end

        if pg.kind == "MEMORY" then
          self:drawPlayBaby(52, 52)
          self:drawPlayCounter(pg.round or 1, 5)
          local arrows = nil
          if pg.phase == "reveal" or pg.phase == "reveal_linger" then
            local shown = pg.phase == "reveal_linger" and #pg.sequence
              or math.max(1, math.min(#pg.sequence, tonumber(pg.revealCount) or 1))
            arrows = {}
            for i = 1, shown do arrows[i] = pg.sequence[i] end
          elseif pg.inputFlash and now < (tonumber(pg.inputFlashUntil) or 0) then
            -- Keep the player's final press visible even if that correct input
            -- already advanced us into BETWEEN/result for the next round.
            arrows = { pg.inputFlash }
          end
          if arrows and #arrows > 0 then
            local gap = 2
            local width = #arrows * 17 + (#arrows - 1) * gap
            local startX = math.floor((160 - width) / 2)
            for i, direction in ipairs(arrows) do
              local image = self.art.play.arrows[direction]
              if image then drawImage(image, startX + (i - 1) * (17 + gap), 37) end
            end
          end
        end
      end

      function state:drawPauseOverlay()
        if self.data.carePaused ~= true then return end
        local label = "PAUSE"
        -- Center the entire native Gen II window on the 160px Nursery panel,
        -- then center the label independently inside it. An 8-tile window is
        -- 64px wide, so tile X=6 puts it exactly at 48..112 around x=80.
        Chrome.box(6, 7, 8, 3)
        Font.draw(label, math.floor((160 - Font.width(label)) / 2), 64)
      end

      function state:drawThoughtBubble()
        -- PLAY minigames use the same Nursery stage as normal care, so a
        -- persistent/temporary thought bubble can otherwise sit directly over
        -- BOUNCE balls, MATCH flags, or MEMORY arrows. Suppress only while the
        -- player is actively playing. RESULT is deliberately excluded so the
        -- happy/ecstatic/sad/angry reaction earned by the game is visible over
        -- the result pose. Do not clear the bubble or alter any COND/timer state.
        if self.playGame and self.playGame.phase ~= "result" then return end

        local bubble = self.thoughtBubble
        local bounds = self.lastBabyBounds
        local kind = self:isSleeping() and "exhausted"
          or (bubble and bubble.kind or self:persistentThoughtKind())
        if not (kind and bounds) then return end
        local image = self.art.thought and self.art.thought[kind]
        if not image then return end
        local x = math.floor(bounds.x + bounds.w / 2 - image:getWidth() / 2)
        local y = math.floor(bounds.y - image:getHeight() + 4)
        x = math.max(0, math.min(160 - image:getWidth(), x))
        y = math.max(31, y)
        drawImage(image, x, y)
      end

      function state:drawEating()
        local eat = self.eating
        if not eat then return end
        local step = eat.sequence[math.min(eat.index, #eat.sequence)]
        local drawStep = step
        local slot = self:activeSlotRecord()

        -- On visible bite beats, official babies using CRYSTAL presentation can
        -- use a hand-picked native frontpic animation pose (open mouth / more
        -- expressive face). The normal two-pose Nursery art remains the
        -- fallback, and NEO presentation is intentionally unchanged.
        if slot and slot.kind == "baby" and slot.spriteStyle == "crystal"
            and eat.biteMarks then
          -- Hold the expressive eating pose for the bite itself and the short
          -- chew beat immediately after it. This makes Smoochum's open mouth,
          -- Cleffa/Igglybuff's happy mouths, etc. clearly visible rather than
          -- flashing for only one authored frame.
          local onBite = eat.biteMarks[eat.index] == true
          local chewingAfterBite = eat.index > 1 and eat.biteMarks[eat.index - 1] == true
          if onBite or chewingAfterBite then
            local actionFrame = NURSERY_CFG.NEO.officialEatFrames[slot.species]
            if actionFrame then
              drawStep = {
                frame = step.frame, x = step.x, y = step.y, flip = step.flip,
                berry = step.berry, actionFrame = actionFrame,
              }
            end
          end
        end

        self.lastBabyBounds = drawBabyStep(self.art, drawStep, slot, self.game)
        if eat.food.anim and step.berry then
          local stages = eat.food.anim == "berry" and self.art.berry
            or (self.art.food and self.art.food[eat.food.anim])
          local image = stages and stages[step.berry]
          if image then
            -- Keep each differently-sized prop centred in the baby's feeding
            -- hand area and bottom-aligned to the original Berry baseline.
            local x = math.floor(56.5 - image:getWidth() / 2)
            local y = 96 - image:getHeight()
            drawImage(image, x, y)
          end
        end
      end

      function state:drawMedicating()
        local med = self.medicating
        if not med then return end
        local step = med.sequence[math.min(med.index, #med.sequence)]
        self.lastBabyBounds = drawBabyStep(self.art, step, self:activeSlotRecord(), self.game)
        local image = self.art.medicine and self.art.medicine[med.medicine and med.medicine.asset]
        if image then drawImage(image, 49, 76) end
      end

      function state:drawSleepingBaby()
        local slot = self:activeSlotRecord()
        if not (slot and slot.kind == "baby") then return end
        local idx = math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
          math.floor(tonumber(self.data.sleepWalkIndex) or tonumber(self.babyWalkIndex) or 1)))
        local base = NURSERY_CFG.BABY_WALK[idx]
        local image = self.art.sleepBassinet
        if image then
          local w, h = image:getWidth(), image:getHeight()
          local x = (base.x or 52) + math.floor((56 - w) / 2)
          local y = (base.y or 52) + (56 - h)
          drawImage(image, x, y)
          -- Use a hand-tuned visible region so the ZZZ bubble sits close to the
          -- basket rather than floating above the full 56x56 canvas.
          self.lastBabyBounds = { x = x + 4, y = y + 6, w = 48, h = 34 }
        else
          self.lastBabyBounds = drawBabyStep(self.art,
            { frame = 1, x = base.x or 52, y = base.y or 52, flip = base.flip == true },
            slot, self.game)
        end
      end

      function state:drawRefusingFood()
        local refuse = self.refusing
        if not refuse then return end
        local step = NURSERY_CFG.FULL_HUNGER_REFUSE[math.min(refuse.index, #NURSERY_CFG.FULL_HUNGER_REFUSE)]
        self.lastBabyBounds = drawBabyStep(self.art, step, self:activeSlotRecord(), self.game)
      end

      function state:drawWaste()
        local count = math.max(0, math.min(NURSERY_CFG.WASTE_MAX,
          math.floor(tonumber(self.data.wasteCount) or 0)))
        if count <= 0 then return end
        for i = 1, count do
          local pos = NURSERY_CFG.WASTE_POSITIONS[i]
          if pos then drawImage(self.art.waste[self.wasteFrame], pos[1], pos[2]) end
        end
      end

      function state:drawPooping()
        local poop = self.pooping
        if not poop then return end
        self:drawWaste()
        local base = NURSERY_CFG.BABY_WALK[math.max(1, math.min(#NURSERY_CFG.BABY_WALK,
          math.floor(tonumber(poop.walkIndex) or 1)))]
        local shake = NURSERY_CFG.POOP_SHAKE[math.max(1, math.min(#NURSERY_CFG.POOP_SHAKE,
          math.floor(tonumber(poop.index) or 1)))] or 0
        self.lastBabyBounds = drawBabyStep(self.art, {
          frame = ((math.floor(tonumber(poop.index) or 1) - 1) % 2) + 1,
          x = (base.x or 52) + shake,
          y = base.y or 52,
          flip = base.flip == true,
        }, self:activeSlotRecord(), self.game)
      end

      function state:drawCleaning()
        local clean = self.cleaning
        if not clean then return end
        -- Cleaning the room is allowed while the baby sleeps, but the baby
        -- itself never wakes, recentres, or animates for it. Only the flush
        -- sweep and waste change around the fixed sleeping pose.
        if self:isSleeping() then
          self:drawSleepingBaby()
        else
          local babyFrame = ((clean.index - 1) % 2) + 1
          self.lastBabyBounds = drawBabyStep(self.art,
            { frame = babyFrame, x = 52, y = 52, flip = false }, self:activeSlotRecord(), self.game)
        end
        self:drawWaste()
        local step = NURSERY_CFG.FLUSH_SWEEP[math.min(clean.index, #NURSERY_CFG.FLUSH_SWEEP)]
        drawImage(self.art.flush, step.x, NURSERY_CFG.FLUSH_Y)
      end

      function state:draw()
        local roomIndex = math.floor(tonumber(self.data.roomIndex) or 1)
        if roomIndex < 1 or roomIndex > #self.art.rooms then roomIndex = 1 end

        local roomSet = (self.data.lightsOn == false) and self.art.roomsLightsOff or self.art.rooms
        drawImage(roomSet[roomIndex], 0, 0)
        drawMeter(self.art, "hunger", self.data.hunger)
        drawMeter(self.art, "fun", self.data.fun)
        drawMeter(self.art, "clean", self.data.clean)
        self.lastBabyBounds = nil

        if self:careAlertNeeded() then
          drawImage(self.art.alert, 6, 12)
        end

        -- Trainer/visitor sprites live in the room BACKGROUND layer. Draw
        -- them before the Babymon, waste and thought bubbles so foreground
        -- baby-facing elements always remain visible when their bounds overlap.
        if not self.playGame then self:drawZeldaTrainer() end

        local active = self:activeSlotRecord()
        if self.playGame then
          self:drawPlayGame()
        elseif self.eating then
          self:drawEating()
        elseif self.medicating then
          self:drawMedicating()
        elseif self.refusing then
          self:drawRefusingFood()
        elseif self.pooping then
          self:drawPooping()
        elseif self.cleaning then
          self:drawCleaning()
        elseif active and active.kind == "egg" then
          -- Align the 40px EggPic's ground line with the 56px babymon art.
          -- From minute seven on, use Crystal's REAL two tilted EggPic frames
          -- and original 4-tick frame order instead of moving the static egg.
          local frame = eggWiggleFrame(active, self.game, self.data.carePaused == true)
          local eggX, eggY = eggTopLeftForCenter(self.art, 84, 108, 1)
          local neoEggSpecies = NURSERY_CFG.NEO.species[active.eggChoice] and active.eggChoice or nil
          drawEggWiggleFrame(self.art, self.game, frame, eggX, eggY, neoEggSpecies)
        elseif active and active.kind == "baby" then
          if self:isSleeping() then
            self:drawSleepingBaby()
          else
            self.lastBabyBounds = drawBabyStep(self.art, self:currentMovementStep(), active, self.game)
          end
        end

        -- Persistent room-state foreground stays visible during feeding,
        -- medicine, refusals, sleep and ordinary Nursery activity. PLAY is the
        -- only mode that intentionally clears room clutter. POOP/CLEAN own
        -- their waste rendering because those animations manipulate it live.
        if not self.playGame and active and active.kind == "baby"
            and not self.pooping and not self.cleaning then
          self:drawWaste()
        end

        -- Thought bubbles are reaction feedback, not menu chrome. Draw them
        -- directly over the babymon but under any modal chooser.
        self:drawThoughtBubble()
        if not (self.foodMenu or self.medicineMenu or self.careMenu or self.callMenu or self.playMenu or self.playGame) then
          self:drawPauseOverlay()
        end

        -- Zelda's lower-right portrait appears for either contextual care
        -- help or an answered CALL request. Future contacts can reuse this
        -- pending-contact foundation with their own portrait/visit behavior.
        if self:zeldaPortraitAvailable() and not self.playGame then drawImage(self.art.zelda, 137, 122) end

        -- The bottom selector is hidden while a PLAY chooser/minigame or other
        -- modal menu owns input, keeping the active control visually obvious.
        local modalOpen = self.playGame or self.playMenu or self.foodMenu or self.medicineMenu
          or self.careMenu or self.callMenu
        if not modalOpen then
          local pos = NURSERY_CFG.SELECTOR_POS[self.cursor]
          if self.cursor ~= 8 or self:zeldaPortraitAvailable() then
            drawImage(self.art.selector, pos[1], pos[2])
          end
        end

        -- Modal Nursery menus always draw last over the middle play space.
        if self.foodMenu then self:drawFoodMenu() end
        if self.medicineMenu then self:drawMedicineMenu() end
        if self.careMenu then self:drawCareMenu() end
        if self.callMenu then self:drawCallMenu() end
        if self.playMenu then self:drawPlayMenu() end
      end

      -- Resolve eggs that finished while the player was outside the Nursery
      -- before the first rendered/update frame. Eggs that finish after this
      -- point are "live" hatches and use the automatic cutscene above.
      state:resolveReadyEggsOffscreen()

      -- Fresh-player onboarding lives inside the Nursery presentation. Zelda
      -- slides in after awarding the Baby Monitor, talks the player through
      -- STATUS -> NEW EGG, remains onscreen while they choose their first Egg,
      -- then gives the basic care rundown and leaves them to raise it.
      --
      -- Keep zeldaIntroAwaitingEgg persistent so quitting/reopening before
      -- choosing an Egg resumes the guided handoff instead of silently
      -- abandoning the tutorial.
      if opts.onboarding == true or state.data.zeldaIntroAwaitingEgg == true then
        state:beginZeldaOnboarding()
      elseif state.data.zeldaTutorialFinishing == true then
        state:finishZeldaOnboarding()
      elseif opts.zeldaHelp == true then
        state:openZeldaContextHelp()
      else
        state:showCriticalNeedThought()
      end

      return state
    end,
  })

  -- Zelda's physical Day-Care interaction menu.  This screen sits over the
  -- overworld and owns only Nursery-specific actions; vanilla Day Care
  -- breeding remains entirely on the original Man/Lady NPCs.
  mod.content.screens:register(ZELDA_SCREEN, {
    new = function(game)
      local state = {
        game = game,
        isOpaque = false,
        page = "main",
        cursor = 1,
        rows = {},
        rowOffset = 1,
        mainOffset = 1,
        message = nil,
      }

      function state:play(name)
        if self.game and self.game.data then Sound.play(self.game.data, name) end
      end

      function state:setMessage(pages, onDone)
        local body = vanillaPages(pages)
        self.game.stack:push(TextBox.new(self.game, body, onDone, { waitButton = true }))
      end

      function state:closeMessage() end

      function state:showAboutCare()
        self:setMessage({
          { "I care for POKeMON", "that are babies." },
          { "You can leave a", "baby EGG with me." },
          { "Your BABY MONITOR", "checks the Nursery" },
          { "from anywhere.", "See me for that." },
          { "Raise a Nursery", "baby to 100" },
          { "FRIENDSHIP to", "adopt it." },
        })
      end

      function state:refreshDepositRows()
        self.rows = eligiblePlayerEggRows(self.game)
        self.cursor = math.max(1, math.min(self.cursor, math.max(1, #self.rows)))
        self.rowOffset = 1
      end

      function state:refreshWithdrawRows()
        self.rows = withdrawablePlayerRows()
        self.cursor = math.max(1, math.min(self.cursor, math.max(1, #self.rows)))
        self.rowOffset = 1
      end

      function state:refreshAdoptRows()
        self.rows = adoptableNurseryRows()
        self.cursor = math.max(1, math.min(self.cursor, math.max(1, #self.rows)))
        self.rowOffset = 1
      end

      function state:keepMainCursorVisible()
        local visible = 5
        local count = #ZELDA_MENU_ITEMS
        self.mainOffset = math.max(1, math.floor(tonumber(self.mainOffset) or 1))
        if self.cursor < self.mainOffset then self.mainOffset = self.cursor end
        if self.cursor > self.mainOffset + visible - 1 then
          self.mainOffset = self.cursor - visible + 1
        end
        self.mainOffset = math.min(self.mainOffset, math.max(1, count - visible + 1))
      end

      function state:keepTransferCursorVisible()
        -- Transfer lists use two-line rows so identifying details stay readable:
        -- DROP OFF shows Pokemon name + gender/level, while WITHDRAW / ADOPT
        -- show SLOT + Pokemon name. Three rows fit cleanly without crowding.
        local visible = (self.page == "deposit" or self.page == "withdraw" or self.page == "adopt") and 3 or 4
        local count = #self.rows
        if count <= visible then self.rowOffset = 1 return end
        self.rowOffset = math.max(1, math.floor(tonumber(self.rowOffset) or 1))
        if self.cursor < self.rowOffset then self.rowOffset = self.cursor end
        if self.cursor > self.rowOffset + visible - 1 then
          self.rowOffset = self.cursor - visible + 1
        end
        self.rowOffset = math.min(self.rowOffset, math.max(1, count - visible + 1))
      end

      function state:enterDeposit()
        local nursery = saveState()
        if not firstOpenNurserySlot(nursery) then
          self.page = "main"
          self:setMessage({ { "The Nursery is", "full right now." } })
          self:play("Sfx_Wrong")
          return
        end
        self.page = "deposit"
        self.cursor = 1
        self:refreshDepositRows()
        if #self.rows == 0 then
          self.page = "main"
          self:setMessage({
            { "No eligible EGG", "or BABYMON." },
          })
          self:play("Sfx_Wrong")
        end
      end

      function state:enterWithdraw()
        self.page = "withdraw"
        self.cursor = 1
        self:refreshWithdrawRows()
        if #self.rows == 0 then
          self.page = "main"
          self:setMessage({
            { "You don't have a", "POKeMON here." },
          })
          self:play("Sfx_Wrong")
        end
      end

      function state:enterAdopt()
        local rows, nurseryBabies = adoptableNurseryRows()
        if #rows == 0 then
          self.page = "main"
          if nurseryBabies > 0 then
            self:setMessage({
              { "A baby needs 100", "FRIENDSHIP first." },
            })
          else
            self:setMessage({
              { "No Nursery baby", "is ready to adopt." },
            })
          end
          self:play("Sfx_Wrong")
          return
        end
        self.page = "adopt"
        self.cursor = 1
        self.rows = rows
        self.rowOffset = 1
      end

      function state:confirmAdoption(row)
        local slot = row and row.slot
        if not slot then return end
        local name = tostring(slot.nickname or slot.species or "BABY")
        self.game.stack:push(TextBox.new(self.game, "Adopt " .. name .. "?", nil, NEO.yesFirst({
          choice = function(yes)
            if not yes then return end
            local ok, destination, detail, first, neoUnlock = adoptNurseryBaby(self.game, row.slotIndex)
            if not ok then
              self:play("Sfx_Wrong")
              local pages
              if destination == "STORAGE FULL" then
                pages = { { "Your party and", "BOXES are full." } }
              elseif destination == "NEEDS 100 FRIENDSHIP" then
                pages = { { "It needs 100", "FRIENDSHIP first." } }
              else
                pages = { { "I can't finish", "that adoption." } }
              end
              self:setMessage(pages)
              return
            end

            self:play("Sfx_CaughtMon")
            self.page = "main"
            self.cursor = 1
            self.mainOffset = 1
            self.rows = {}
            self.rowOffset = 1
            local pages = {}
            if first then
              pages[#pages + 1] = { "It's official!", "Adoption complete!" }
              pages[#pages + 1] = { "Take good care of", name .. "!" }
            else
              pages[#pages + 1] = { "Adoption complete!", "Take good care!" }
            end
            if destination == "box" then
              pages[#pages + 1] = { "Party is full.", "Sent to BOX " .. tostring(detail) .. "." }
            end
            self:setMessage(pages)
          end,
        })))
      end

      function state:openNursery()
        -- Remove Zelda's menu first so leaving the Nursery returns directly to
        -- the Day Care map instead of reopening a stale transfer menu.
        self.game.stack:pop()
        mod.ui.push(self.game, SCREEN)
      end

      function state:updateMessage(input)
        local m = self.message
        if not m then return false end
        if input:wasPressed("a") or input:wasPressed("b") then
          m.index = m.index + 1
          if m.index > #(m.pages or {}) then self:closeMessage() end
        end
        return true
      end

      function state:updateMain(input)
        if input:wasPressed("b") then self.game.stack:pop() return end
        if input:wasPressed("up") then
          self.cursor = self.cursor - 1
          if self.cursor < 1 then self.cursor = #ZELDA_MENU_ITEMS end
          self:keepMainCursorVisible()
        elseif input:wasPressed("down") then
          self.cursor = self.cursor + 1
          if self.cursor > #ZELDA_MENU_ITEMS then self.cursor = 1 end
          self:keepMainCursorVisible()
        elseif input:wasPressed("a") then
          local item = ZELDA_MENU_ITEMS[self.cursor]
          if item == "NURSERY" then
            self:play("Sfx_Menu")
            self:openNursery()
          elseif item == "DROP OFF" then
            self:enterDeposit()
          elseif item == "WITHDRAW" then
            self:enterWithdraw()
          elseif item == "ADOPT" then
            self:enterAdopt()
          elseif item == "ABOUT CARE" then
            self:showAboutCare()
          else
            self.game.stack:pop()
          end
        end
      end

      function state:updateTransfer(input)
        if input:wasPressed("b") then
          self.page = "main"
          self.cursor = 1
          self.rows = {}
          self.rowOffset = 1
          return
        end
        local count = #self.rows
        if count <= 0 then self.page = "main" return end
        if input:wasPressed("up") then
          self.cursor = self.cursor - 1
          if self.cursor < 1 then self.cursor = count end
          self:keepTransferCursorVisible()
        elseif input:wasPressed("down") then
          self.cursor = self.cursor + 1
          if self.cursor > count then self.cursor = 1 end
          self:keepTransferCursorVisible()
        elseif input:wasPressed("a") then
          local row = self.rows[self.cursor]
          if self.page == "adopt" then
            self:confirmAdoption(row)
          elseif self.page == "deposit" then
            local ok, detail, depositedKind = depositPlayerEgg(self.game, row and row.partyIndex)
            if ok then
              self:play(depositedKind == "baby" and "Sfx_Menu" or "Sfx_GetEgg")
              self.page = "main"
              self.cursor = 1
              self.rows = {}
              self.rowOffset = 1
              local noun = depositedKind == "baby" and "BABYMON" or "EGG"
              self:setMessage({
                { "I'll take care", "of this " .. noun .. "." },
                { "It's in Nursery", "SLOT " .. tostring(detail) .. "." },
              })
            else
              self:play("Sfx_Wrong")
              self:setMessage({ { "I can't take it", "right now: " .. tostring(detail) } })
            end
          else
            local ok, detail, returnedKind = withdrawPlayerResident(self.game, row and row.slotIndex)
            if ok then
              self:play("Sfx_Menu")
              self.page = "main"
              self.cursor = 1
              self.rows = {}
              self.rowOffset = 1
              local noun = returnedKind == "baby" and "BABYMON" or "EGG"
              self:setMessage({
                { "Here's your " .. noun, "from SLOT " .. tostring(detail) .. "." },
                { "Take good care of", "it!" },
              })
            else
              self:play("Sfx_Wrong")
              local line = detail == "PARTY FULL" and "Your party is full." or tostring(detail)
              self:setMessage({ { "I can't return it", "right now." }, { line, "" } })
            end
          end
        end
      end

      function state:update()
        local input = self.game and self.game.input
        if not input then return end
        if self.page == "main" then self:updateMain(input)
        else self:updateTransfer(input) end
      end

      function state:drawPanel()
        local G = love.graphics
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", 8, 8, 144, 120)
        G.setColor(0, 0, 0, 1)
        Chrome.textbox(1, 1, 16, 13)
      end

      function state:drawMessage()
        local m = self.message
        if not m then return end
        local page = (m.pages or {})[math.max(1,
          math.min(m.index, #(m.pages or {})))] or { "ZELDA" }
        Font.draw("ZELDA", 16, 24)
        Font.draw(page[1] or "", 16, 56)
        Font.draw(page[2] or "", 16, 72)
        Chrome.print("▼", 17, 14)
      end

      function state:drawMain()
        Font.draw("ZELDA", 16, 24)
        self:keepMainCursorVisible()
        local first = self.mainOffset or 1
        local last = math.min(#ZELDA_MENU_ITEMS, first + 4)
        for i = first, last do
          local visual = i - first
          local y = 40 + visual * 16
          if i == self.cursor then Chrome.cursor(2, math.floor(y / 8)) end
          Font.draw(ZELDA_MENU_ITEMS[i], 27, y)
        end
        if first > 1 then Chrome.print("▲", 17, 3) end
        if last < #ZELDA_MENU_ITEMS then Chrome.print("▼", 17, 13) end
      end

      function state:drawTransfer()
        local title
        if self.page == "deposit" then title = "DROP OFF WHICH?"
        elseif self.page == "adopt" then title = "ADOPT WHICH?"
        else title = "WITHDRAW WHICH?" end
        Font.draw(title, 16, 24)
        self:keepTransferCursorVisible()
        local first = self.rowOffset or 1
        local twoLineRows = self.page == "deposit" or self.page == "withdraw" or self.page == "adopt"
        local visible = twoLineRows and 3 or 4
        local last = math.min(#self.rows, first + visible - 1)
        for i = first, last do
          local row = self.rows[i]
          local visual = i - first
          if twoLineRows then
            local y = 40 + visual * 28
            if i == self.cursor then Chrome.cursor(2, math.floor(y / 8)) end

            if self.page == "deposit" then
              Font.draw(row.nameLabel or row.label or "EGG", 27, y)
              if row.detailLabel and row.detailLabel ~= "" then
                Font.draw(row.detailLabel, 35, y + 12)
              end
            else
              Font.draw(row.slotLabel or ("SLOT " .. tostring(row.slotIndex or i)), 27, y)
              Font.draw(row.nameLabel or row.label or "BABY", 35, y + 12)
            end
          else
            local y = 40 + visual * 16
            if i == self.cursor then Chrome.cursor(2, math.floor(y / 8)) end
            Font.draw(row.label or "EGG", 27, y)
          end
        end
        if first > 1 then Chrome.print("▲", 17, 3) end
        if last < #self.rows then Chrome.print("▼", 17, 13) end
      end

      function state:draw()
        self:drawPanel()
        if self.page == "main" then self:drawMain()
        else self:drawTransfer() end
      end

      return state
    end,
  })

  local function worldTextPages(world, pages, onDone)
    -- Feed the complete conversation to Crystal's normal two-line TextBox.
    -- Explicit page breaks mean every page waits for A/B; there is no CONT
    -- scrolling and no hand-drawn dialogue layout to create odd spacing.
    world:showText(vanillaPages(pages), onDone)
  end

  local function configureBabyMonitorItem(game)
    local items = game and game.data and game.data.items
    local def = items and items[BABY_MONITOR_ID]
    if not def then return nil end
    -- These are the exact fields Gen 2's PackMenu reads. A mod-registered id
    -- otherwise defaults to the general ITEM pocket.
    def.pocket = "KEY_ITEM"
    def.canToss = false
    def.canSelect = true
    def.fieldMenu = "ITEMMENU_CLOSE"
    def.battleMenu = "ITEMMENU_NOUSE"
    def.description = "Checks BABYMON.\nOpens NURSERY."
    return def
  end

  local function ensureBabyMonitorInventory(game, playSfx)
    if not (game and game.save) then return false end
    configureBabyMonitorItem(game)
    game.save.inventory = game.save.inventory or {}
    if (tonumber(game.save.inventory[BABY_MONITOR_ID]) or 0) > 0 then return true end
    local ok = Bag.add(game.save, BABY_MONITOR_ID, 1, game.data)
    if not ok then
      -- A full vanilla KEY ITEM pocket should not strand an already-earned
      -- mod key item. Preserve acquisition order and add this one extra slot.
      local order = Bag.order(game.save, game.data)
      order[#order + 1] = BABY_MONITOR_ID
      game.save.inventory[BABY_MONITOR_ID] = 1
      ok = true
    end
    if ok and playSfx and game.data then Sound.play(game.data, "Sfx_Item") end
    return ok
  end

  local function giveBabyMonitor(game, world, after)
    local s = saveState()
    s.zeldaIntroduced = true
    s.zeldaAccepted = true
    s.hasBabyMonitor = true
    mod.save:set("babycare", s)
    ensureBabyMonitorInventory(game, true)
    world:showText("ZELDA gave you the\nBABY MONITOR!", after)
  end

  local function startFreshZeldaTutorial(game, world)
    local s = saveState()
    -- Fresh players get the original guided handoff: Zelda awards the Monitor
    -- in the Day Care, then immediately joins the player inside the Nursery
    -- and stays there until their first Nursery Egg has been chosen.
    s.zeldaIntroAwaitingEgg = true
    s.zeldaTutorialSeen = false
    mod.save:set("babycare", s)
    giveBabyMonitor(game, world, function()
      mod.ui.push(game, SCREEN, { onboarding = true })
    end)
  end

  local function acceptZeldaHelp(game, world)
    local s = saveState()
    local occupied = false
    for i = 1, SLOT_COUNT do if s.slots and s.slots[i] then occupied = true break end end
    if occupied then
      -- Existing dev/prototype saves keep their residents. They still meet
      -- Zelda and receive the Monitor, but are not forced through a first-Egg
      -- tutorial that could collide with occupied slots or an old cooldown.
      s.zeldaTutorialSeen = true
      s.zeldaIntroAwaitingEgg = false
      mod.save:set("babycare", s)
      giveBabyMonitor(game, world, function()
        worldTextPages(world, {
          { "You already help", "with the Nursery!" },
          { "Use BABY MONITOR", "to check Nursery." },
        }, function() mod.ui.push(game, ZELDA_SCREEN) end)
      end)
    else
      startFreshZeldaTutorial(game, world)
    end
  end

  local function askZeldaToHelp(game, world, firstMeeting)
    local question = firstMeeting
      and "Would you like to\nhelp raise them?"
      or  "Would you like to\nhelp with BABYMON?"
    world:showText(question, function()
      world:askYesNo(function(yes)
        if yes then
          acceptZeldaHelp(game, world)
        else
          local s = saveState()
          s.zeldaIntroduced = true
          s.zeldaAccepted = false
          mod.save:set("babycare", s)
          worldTextPages(world, {
            { "Thanks for your", "time anyway!" },
            { "Come back anytime", "if interested." },
          })
        end
      end)
    end, true)
  end

  local function talkToZelda(game, world, npc)
    if npc and npc.facePlayer and world and world.player then
      npc:facePlayer(world.player)
    end
    local s = saveState()
    if s.zeldaAccepted == true then
      mod.ui.push(game, ZELDA_SCREEN)
      return true
    end
    if s.zeldaIntroduced == true then
      worldTextPages(world, {
        { "Hi again!", "Changed your mind?" },
      }, function() askZeldaToHelp(game, world, false) end)
      return true
    end
    worldTextPages(world, {
      { "Hi! I'm ZELDA.", "The DAY-CARE LADY" },
      { "is my mother.", "I help her here." },
      { "I look after young", "BABY POKeMON." },
      { "They're too young", "to live alone." },
    }, function() askZeldaToHelp(game, world, true) end)
    return true
  end

  local function ensureZeldaOnDayCare(ev)
    if not ev or ev.mapId ~= "DAY_CARE" then return end
    local map = ev.map
    local def = map and map.def
    for _, obj in ipairs((def and def.objects) or {}) do
      if obj.name == "ZELDA" and obj.owner == mod.id then return end
    end
    local npcId, err = mod.world:spawnNpc("DAY_CARE", {
      name = "ZELDA",
      sprite = "SPRITE_POKEFAN_F",
      x = 5, y = 4,
      movement = 8, -- SPRITEMOVEDATA_STANDING_LEFT
      radius = { x = 0, y = 0 },
      hours = { -1, -1 },
      palette = 9, -- PAL_NPC_BLUE / light-blue overworld palette
      type = 0, sight = 0,
    })
    if npcId then
      mod.log:info("PokéCradle placed Zelda under the Day-Care Lady (%s)", tostring(npcId))
    else
      mod.log:warn("PokéCradle could not place Zelda: %s", tostring(err))
    end
  end

  mod.events:on("map.entered", ensureZeldaOnDayCare, 100000)

  -- Gen 2's A-press path dispatches NPC talk through the Gen1 compatibility
  -- facade (`OverworldController.talkTo`) rather than Runtime's `world.talk`
  -- hook.  Hook the actual Crystal seam so Zelda is a real interactable NPC.
  -- Return true only for the runtime object owned by this mod; every vanilla
  -- Day-Care object and every other mod's NPC falls through unchanged.
  local previousTalkTo = OverworldController.talkTo
  OverworldController.talkTo = function(world, npc)
    local def = npc and npc.def
    if def and def.name == "ZELDA" and def.owner == mod.id then
      local game = world and world.game
      if game then
        talkToZelda(game, world, npc)
        return true
      end
    end
    if previousTalkTo then return previousTalkTo(world, npc) end
    return false
  end

  -- Optional PokeSurvive interoperability. Its camping system calls
  -- PokeSurviveGoldTime.advance(..., 480, "camp"). Wrap only that public seam:
  -- the displayed RTC advances eight hours, while Neo Nursery's real-time care
  -- meters do NOT. Only sleep/TIRED bookkeeping follows the skipped game time.
  local function installPokeSurviveCampCompat(game)
    local clock = rawget(_G, "PokeSurviveGoldTime")
    if type(clock) ~= "table" or type(clock.advance) ~= "function" then return false end
    if clock._neoNurseryCampCompat == true then return true end

    local previousAdvance = clock.advance
    clock.advance = function(g, minutes, reason)
      local beforeMinute = currentGameMinuteOfDay(g or game)
      local result = previousAdvance(g, minutes, reason)
      if result == true and tostring(reason or "") == "camp" and (tonumber(minutes) or 0) > 0 then
        local s = saveState()
        advanceSyntheticSleepClock(s, g or game, beforeMinute, minutes)
        mod.save:set("babycare", s)
      end
      return result
    end
    clock._neoNurseryCampCompat = true
    return true
  end

  -- Older dev saves may already have Zelda's monitor flag from v0.0.26-28.
  -- Migrate those saves silently into the real KEY ITEMS pocket on load.
  mod.events:on("game.ready", function(ev)
    local game = ev and ev.game
    if not game then return end
    configureBabyMonitorItem(game)
    installPokeSurviveCampCompat(game)
    local s = saveState()
    if s.hasBabyMonitor == true then ensureBabyMonitorInventory(game, false) end
  end, 100000)

  -- While the Nursery is the visible opaque screen, recolor only the window
  -- space outside Crystal's 160x144 UI canvas. The game canvas itself is
  -- blitted after render.letterbox, so this paints the formerly white surround
  -- pink without touching the Nursery art or menus.
  mod.hooks:wrap("render.letterbox", function(next, ctx)
    next(ctx)
    local stack = Game and Game.stack
    local states = stack and stack.states or nil
    local nurseryVisible = false
    for i = #(states or {}), 1, -1 do
      local s = states[i]
      if s and s.babycareNursery == true then
        nurseryVisible = true
        break
      end
    end

    -- Do not paint Neo Nursery's pink surround over a full-screen/widescreen
    -- state that has been pushed above the Nursery. Gen1Recomp raises the
    -- render.letterbox hook *after* such a screen draws its own widescreen
    -- presentation; painting the full window here would therefore cover the
    -- entire cutscene. This is exactly what happened to the vanilla Egg hatch:
    -- its music/SFX continued normally, but only this #EF9AA4 field remained.
    local top = stack and stack.top and stack:top() or nil
    local topOwnsWidescreen = false
    if top and type(top.drawsWidescreen) == "function" then
      local ok, owns = pcall(top.drawsWidescreen, top)
      topOwnsWidescreen = ok and owns == true
    end

    if nurseryVisible
       and not topOwnsWidescreen
       and not (ctx and ctx.worldActive) then
      local G = love.graphics
      G.setColor(239 / 255, 154 / 255, 164 / 255, 1)
      G.rectangle("fill", 0, 0,
        (ctx and ctx.ww) or G.getWidth(),
        (ctx and ctx.wh) or G.getHeight())
      G.setColor(1, 1, 1, 1)
    end
  end, 100000)

  -- The Baby Monitor can be registered with SEL and opened directly from the
  -- overworld SELECT button, just like Crystal's registerable key items.
  -- Keep the care clock moving while the player is out in the overworld so
  -- the alert can appear at the moment a need becomes critical, rather than
  -- only after reopening the Nursery. The same top-level care state is used by
  -- the Nursery screen, so this does not create a second timer.
  local overworldCareAlertImage = nil
  local overworldCareLastPoll = nil

  local function overworldCareAlertNeeded(game)
    local s = saveState()
    if s.carePaused == true then return false end
    local active = s.slots and s.slots[s.activeSlot or 1]
    if not (active and active.kind == "baby") then return false end

    local now = wallNow()
    if overworldCareLastPoll ~= now then
      overworldCareLastPoll = now
      -- Advance all residents from their own checkpoints. The selected slot is
      -- mirrored into the top-level HUD fields by the helper.
      advanceAllResidentCare(s, now, game, false)
    end

    return clampMeter(s.hunger) == 0
      or clampMeter(s.fun) == 0
      or clampMeter(s.clean) == 0
      or (type(s.sickness) == "table" and s.sickness.kind ~= nil)
  end

  -- Draw the overworld care-alert icon as a flat UI overlay after the map has
  -- rendered. Keep three native pixels of padding and scale the supplied art
  -- to 3x with nearest-neighbour filtering so it is impossible to miss.
  local previousWorldDraw = Gen2World.draw
  Gen2World.draw = function(world, ...)
    local result = previousWorldDraw(world, ...)
    if world and world.game and overworldCareAlertNeeded(world.game) then
      if not overworldCareAlertImage then
        local ok, image = pcall(mod.assets.image, mod.assets, "assets/care_alert_overworld.png")
        if ok and image then
          if image.setFilter then image:setFilter("nearest", "nearest") end
          overworldCareAlertImage = image
        end
      end
      if overworldCareAlertImage then
        local G = love.graphics
        G.setColor(1, 1, 1, 1)
        G.draw(overworldCareAlertImage, 3, 3, 0, 3, 3)
        G.setColor(1, 1, 1, 1)
      end
    end
    return result
  end

  local previousUseSelectItem = Gen2World.useSelectItem
  Gen2World.useSelectItem = function(world)
    local id = world and world.registeredItemId and world:registeredItemId() or nil
    if id == BABY_MONITOR_ID and not (world.battleActive or world:busy()) then
      local game = world.game
      if game then mod.ui.push(game, SCREEN) end
      return "baby_monitor", BABY_MONITOR_ID
    end
    return previousUseSelectItem(world)
  end

  -- Gen 2's Pack has no public custom-field-item dispatch yet. Intercept only
  -- this registered item at PackMenu's USE seam, close the START/PACK stack,
  -- then open the Nursery. Every vanilla item falls through untouched.
  local previousPackUseSelected = PackMenu.useSelected
  PackMenu.useSelected = function(self)
    local row = self.rows and self.rows[self.index]
    if row and row.id == BABY_MONITOR_ID and not self:inBattle() then
      if self.storeCursor then self:storeCursor() end
      local game = self.game
      local stack = game and game.stack
      if stack and stack.clear then stack:clear() end
      if game then mod.ui.push(game, SCREEN) end
      return
    end
    return previousPackUseSelected(self)
  end

end

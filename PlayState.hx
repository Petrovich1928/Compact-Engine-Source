package states;

import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Rating;
import backend.HardcoreMode;
import backend.TimelessMode;
import backend.DynamicHealthbarColor;
import backend.HealthLock;
import backend.SecondChance;
import backend.MetadataDisplay;
import backend.FairPlayChecker;
import backend.InfectMode;
import substates.InfectedSubState;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;


import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash
import openfl.filters.ShaderFilter;
#end

import shaders.ErrorHandledShader;

import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;
import states.stages.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
import psychlua.FunkinLua;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if HSCRIPT_ALLOWED
import psychlua.HScript.HScriptInfos;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
class PlayState extends MusicBeatState
{
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

public static var ratingStuff:Array<Dynamic> = [
    ['just close the game.', 0.2], //From 0% to 19%
    ['damnit', 0.5], //From 20% to 49%
    ['keep trying', 0.55], //From 50% to 54%
    ['not bad!', 0.65], //From 55% to 64%
    ['mid', 0.69], //From 65% to 68%
    ['pefretc', 0.75], //69% (Easter egg)
    ['good, good', 0.85], //From 70% to 84%
    ['so great!', 0.95], //From 85% to 94%
    ['amazing!!', 1], //From 95% to 99%
    ['PERFECT!!!', 1] //100%
];
public static var storyWeekID:String = "";
public var hardcoreMode:Bool = false;
public var timelessMode:Bool = false;
public var secondChanceEnabled:Bool = false;

// ── InfectMode ────────────────────────────────────────────────────────
public var infectModeEnabled:Bool = false;
var _infectLayer1:FlxSprite;
var _infectLayer2:FlxSprite;
var _infectLayer3:FlxSprite;
var _infectedSubStateOpened:Bool = false;

	private var _oppDrainPaused:Bool = false;
private var _oppDrainCounter:Int = 0;
private var _oppDrainAmount:Float = 0.03 * ClientPrefs.data.OpponentDMGmult;
private var _oppMinHealth:Float = 0.2;
private var _oppResumeThreshold:Float = 0.21;
private var _oppDiffAllowed:Bool = false;
public var dynamicHealthbarColors:Bool = false;
private var lastOpponentChar:String = '';
private var lastPlayerChar:String = '';
private var visualHealth:Float = 1;
private var smoothHealthSpeed:Float = 10;
public static var isWelcomeTutorial:Bool = false;

	//event variables
	private var isCameraOnForcedPos:Bool = false;
	var infoText:FlxText;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var holdSplashes:Array<FlxSprite> = [];
	public var holdSplashTimers:Array<Float> = [];
	public var holdSplashActive:Array<Bool> = [];

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI(default, set):String = "normal";
	public static var uiPrefix:String = "";
	public static var uiPostfix:String = "";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function set_stageUI(value:String):String
	{
		uiPrefix = uiPostfix = "";
		if (value != "normal")
		{
			uiPrefix = value.split("-pixel")[0].trim();
			if (value == "pixel" || value.endsWith("-pixel")) uiPostfix = "-pixel";
		}
		return stageUI = value;
	}

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var opponentStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var playerStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;

	// Opponent combo system
	public var opponentCombo:Int = 0;
	public var opponentComboGroup:FlxSpriteGroup;

	public var healthBar:Bar;
	public var timeBar:Bar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;
	public var healthLockEnabled:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	// ── OpponentPlay ──────────────────────────────────────────────────────
	public var opponentPlayMode:Bool = false;
	// Separate score counters saved across states
	public static var opponentSongScore:Int  = 0;
	public static var opponentSongMisses:Int = 0;
	public static var opponentSongHits:Int   = 0;
	public static var opponentRatingPercent:Float = 0.0;
	// Grey-blue miss overlay drawn over dad sprite
	var _oppMissOverlay:FlxSprite = null;
	var _oppMissOverlayTimer:Float = 0.0;
	var _oppMissTintChar:Character = null;
	// ──────────────────────────────────────────────────────────────────────
	
	// Fair Play tracking
	public var wasEverUnfair:Bool = false; // Если хоть раз был чит - навсегда нечестная
	
	public var pressMissDamage:Float = 0.05;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;
	public var cheatNoticeTxt:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var campaignTotalPlayed:Int = 0;
	public static var campaignNotesHit:Float  = 0.0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;
	private var resetInLast10Sec:Bool = false;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	private var lastHealthPercent:Float = 100;

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	private static var _lastLoadedModDirectory:String = '';
	public static var nextReloadAll:Bool = false;
	override public function create()
	{
		//trace('Playback Rate: ' + playbackRate);
		trace('[InfectMode] PlayState.create() START — infectMode=' + ClientPrefs.data.infectMode);
		_lastLoadedModDirectory = Mods.currentModDirectory;
		Paths.clearStoredMemory();
		if(nextReloadAll)
		{
			Paths.clearUnusedMemory();
			Language.reloadPhrases();
		}
		nextReloadAll = false;

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		// OpponentPlay init — try getGameplaySetting first (standard Psych way),
		// then fall back to direct ClientPrefs.data field
		var _oppPlayRaw:Dynamic = null;
		try { _oppPlayRaw = ClientPrefs.getGameplaySetting('opponentplay'); } catch(_e:Dynamic) {}
		if (_oppPlayRaw == null || _oppPlayRaw == false || _oppPlayRaw == 0)
			try { _oppPlayRaw = Reflect.getProperty(ClientPrefs.data, 'opponentPlay'); } catch(_e:Dynamic) {}
		opponentPlayMode = (_oppPlayRaw == true || _oppPlayRaw == 1);
		trace('[OpponentPlay] opponentPlayMode=' + opponentPlayMode + ' (raw=' + _oppPlayRaw + ')');
		if (opponentPlayMode) {
			opponentSongScore   = 0;
			opponentSongMisses  = 0;
			opponentSongHits    = 0;
			opponentRatingPercent = 0.0;
		}
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		persistentUpdate = true;
		persistentDraw = true;

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

if (isStoryMode)
{
	var currentWeek = WeekData.getCurrentWeek();
	if (currentWeek != null)
		detailsText = "The choosed group: " + currentWeek.weekName;
	else
		detailsText = "Story Mode";
}
else
	detailsText = "The choosen one.";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		// Knowledge-DEMO: force Rude difficulty (case-insensitive)
		if (songName.toLowerCase() == "knowledge-demo")
		{
			storyDifficulty = 1;
			Difficulty.copyFrom(["Rude"]);
		}
				if(SONG.stage == null || SONG.stage.length < 1)
			SONG.stage = StageData.vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));

		curStage = SONG.stage;

var stageData:StageFile = StageData.getStageFile(curStage);
if (stageData == null)
{
	trace('WARNING: StageData for "$curStage" is null! Using defaults.');
	stageData = {
		directory: "",
		defaultZoom: 0.9,
		isPixelStage: false,
		stageUI: "normal",
		
		boyfriend: [770, 100],
		girlfriend: [400, 130],
		opponent: [100, 100],
		hide_girlfriend: false,
		
		camera_boyfriend: [0, 0],
		camera_opponent: [0, 0],
		camera_girlfriend: [0, 0],
		camera_speed: 1
	};
}
defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage == true) //Backward compatibility
			stageUI = "pixel";

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new StageWeek1(); 			//Week 1
			case 'spooky': new Spooky();				//Week 2
			case 'philly': new Philly();				//Week 3
			case 'limo': new Limo();					//Week 4
			case 'mall': new Mall();					//Week 5 - Cocoa, Eggnog
			case 'mallEvil': new MallEvil();			//Week 5 - Winter Horrorland
			case 'school': new School();				//Week 6 - Senpai, Roses
			case 'schoolEvil': new SchoolEvil();		//Week 6 - Thorns
			case 'tank': new Tank();					//Week 7 - Ugh, Guns, Stress
			case 'phillyStreets': new PhillyStreets(); 	//Weekend 1 - Darnell, Lit Up, 2Hot
			case 'phillyBlazin': new PhillyBlazin();	//Weekend 1 - Blazin
		}
		if(isPixelStage) introSoundsSuffix = '-pixel';

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gfGroup.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		
		if(stageData.objects != null && stageData.objects.length > 0)
		{
			var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup, boyfriendGroup, this);
			for (key => spr in list)
				if(!StageData.reservedNames.contains(key))
					variables.set(key, spr);
		}
		else
		{
			add(gfGroup);
			add(dadGroup);
			add(boyfriendGroup);
		}
		
#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
// "SCRIPTS FOLDER" SCRIPTS
for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
{
	if (folder != null && FileSystem.exists(folder) && FileSystem.isDirectory(folder))
	{
		for (file in FileSystem.readDirectory(folder))
		{
			#if LUA_ALLOWED
			if(file.toLowerCase().endsWith('.lua'))
				new FunkinLua(folder + file);
			#end

			#if HSCRIPT_ALLOWED
			if(file.toLowerCase().endsWith('.hx'))
				initHScript(folder + file);
			#end
		}
	}
}
#end		
		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if(gf != null) startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		uiGroup = new FlxSpriteGroup();
		comboGroup = new FlxSpriteGroup();
		opponentComboGroup = new FlxSpriteGroup();
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(opponentComboGroup);
		add(comboGroup);
		add(uiGroup);
		add(noteGroup);

		Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
		timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		if(ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44;
		if(ClientPrefs.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		// Start collapsed — will tween to full width when song begins
		timeBar.scale.x = 0.01;
		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		noteGroup.add(strumLineNotes);

		if(ClientPrefs.data.timeBarType == 'Song Name')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		generateSong();

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject();
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return visualHealth, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

if (healthLockEnabled && HealthLock.enabled) {
    HealthLock.createLockStrip(healthBar);
    if (HealthLock.lockStrip != null)
        uiGroup.add(HealthLock.lockStrip);
    trace('[HealthLock] lockStrip добавлен в uiGroup');
}

		visualHealth = health;

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

dynamicHealthbarColors = ClientPrefs.data.dynamicHBcolors;
DynamicHealthbarColor.enabled = dynamicHealthbarColors;

if (dynamicHealthbarColors)
{
    DynamicHealthbarColor.init();
    

    var oppColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
    var plyColor = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);

    DynamicHealthbarColor.checkCharacters(dad.curCharacter, boyfriend.curCharacter, oppColor, plyColor);
    
    lastOpponentChar = dad.curCharacter;
    lastPlayerChar = boyfriend.curCharacter;
}

		if (ClientPrefs.data.iconBounce == 'SDefence') {} // пустое тело — исправлен баг висячего if

		hardcoreMode = ClientPrefs.getGameplaySetting('hardcoremode');
HardcoreMode.enabled = hardcoreMode;
if (hardcoreMode)
{
    health = 2;
    HardcoreMode.init();
}

timelessMode = ClientPrefs.getGameplaySetting('timelessmode');
TimelessMode.enabled = timelessMode;

{
    iconP1.origin.x = 0;
    iconP2.origin.x = iconP2.width;
}

healthLockEnabled = ClientPrefs.getGameplaySetting('healthlock');
HealthLock.enabled = healthLockEnabled;
if (healthLockEnabled) {
    HealthLock.init();
}

secondChanceEnabled = ClientPrefs.getGameplaySetting('secondchance');
SecondChance.enabled = secondChanceEnabled;
if (secondChanceEnabled) {
    SecondChance.init();
    SecondChance.addToGroup(uiGroup, camHUD);
}

		initInfectMode(); // ── InfectMode init ──


		// ── Score HUD: left side, just below vertical centre ────────────────
		scoreTxt = new FlxText(12, Std.int(FlxG.height * 0.52), 320, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.5;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		uiGroup.add(scoreTxt);

		// ── Cheat / unfair notice (shown below healthBar when cheating) ───────
		cheatNoticeTxt = new FlxText(0, healthBar.y + (ClientPrefs.data.downScroll ? -30 : 26), FlxG.width, "", 16);
		cheatNoticeTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		cheatNoticeTxt.scrollFactor.set();
		cheatNoticeTxt.borderSize = 1.5;
		cheatNoticeTxt.visible = false;
		uiGroup.add(cheatNoticeTxt);

		botplayTxt = new FlxText(400, healthBar.y - 90, FlxG.width - 800, Language.getPhrase("Botplay").toUpperCase(), 32);
botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
botplayTxt.scrollFactor.set();
botplayTxt.borderSize = 1.25;
botplayTxt.visible = cpuControlled;
uiGroup.add(botplayTxt);
if(ClientPrefs.data.downScroll)
    botplayTxt.y = healthBar.y + 70;
	uiGroup.add(botplayTxt);
applyBotplayText();

// Detect Knowledge-DEMO song — swap font and label
var _isKathzeDemo:Bool = (songName != null && songName.toLowerCase() == "knowledge-demo");
var _infoFont:String = _isKathzeDemo ? "AKVcr.ttf" : "vcr.ttf";
// Build version label: "Secondary Defence 1.1.2 / SongName - Difficulty"
var _rawSong:String  = (SONG != null && SONG.song != null) ? SONG.song : "";
var _rawDiff:String  = storyDifficultyText != null ? storyDifficultyText : Difficulty.getString();
var _verLine:String  = _isKathzeDemo ? "A.H.N.i. Kathze 0.1B" : "SECONDARY DEFENCE 1.1.2";
var _infoLabel:String = _verLine + "\n" + _rawSong.toUpperCase() + " - " + _rawDiff.toUpperCase();
infoText = new FlxText(10, FlxG.height - 44, 0, _infoLabel, 16);
infoText.setFormat(Paths.font(_infoFont), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
infoText.borderSize = 2;
infoText.scrollFactor.set();
infoText.cameras = [camHUD];
uiGroup.add(infoText);
// Knowledge-DEMO: also replace ALL HUD text fonts to AKVcr
if (_isKathzeDemo) {
    // Swap difficulty to Rude-only (index 1), lock selection
    storyDifficulty = 1;
    Difficulty.copyFrom(["Rude"]);
    // Replace vcr.ttf with AKVcr.ttf in scoreTxt and timeTxt
    new FlxTimer().start(0.05, function(_) {
        if (scoreTxt != null) scoreTxt.font = Paths.font("AKVcr.ttf");
        if (timeTxt  != null) timeTxt.font  = Paths.font("AKVcr.ttf");
        if (botplayTxt != null) botplayTxt.font = Paths.font("AKVcr.ttf");
    });
}

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];
		opponentComboGroup.cameras = [camHUD];

		startingSong = true;

		#if LUA_ALLOWED
		for (notetype in noteTypes)
			startLuasNamed('custom_notetypes/' + notetype + '.lua');
		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			for (file in FileSystem.readDirectory(folder))
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		if(eventNotes.length > 0)
		{
			for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		startCallback();
		RecalculateRating(false, false);

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		//PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if(ClientPrefs.data.hitsoundVolume > 0) Paths.sound('hitsound');
		if(!ClientPrefs.data.ghostTapping) for (i in 1...4) Paths.sound('missnote$i');
		Paths.image('alphabet');

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if(Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		stagesFunc(function(stage:BaseStage) stage.createPost());
		callOnScripts('onCreatePost');
		
		var splash:NoteSplash = new NoteSplash();
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		lastHealthPercent = CoolUtil.floorDecimal((health / 2) * 100, 2);

		// Song Metadata system
var metaAuthor:String = "";
var metaExtra:String = "";
var metaShowStart:Bool = false;

try {
    if (PlayState.SONG.metadata_author != null)
        metaAuthor = PlayState.SONG.metadata_author;
    if (PlayState.SONG.metadata_extra != null)
        metaExtra = PlayState.SONG.metadata_extra;
    if (PlayState.SONG.metadata_showStart != null)
        metaShowStart = PlayState.SONG.metadata_showStart;
} catch(e:Dynamic) {
    trace('[MetadataDisplay] Error loading metadata: $e');
}

MetadataDisplay.init(PlayState.SONG.song, metaAuthor, metaExtra, metaShowStart);
MetadataDisplay.createUI(PlayState.SONG.song);
if (MetadataDisplay.metadataBox != null) {
    uiGroup.add(MetadataDisplay.metadataBox);
    MetadataDisplay.metadataBox.cameras = [camHUD];
}


		createHoldSplashes();

		super.create();

try {
    var optionEnabled:Bool = false;
    try { optionEnabled = ClientPrefs.data.opponentCanKill; } catch(e:Dynamic) {
        try { optionEnabled = ClientPrefs.data.gameplaySettings.get('opponentCanKill'); } catch(e:Dynamic) { optionEnabled = false; }
    }

    var diffName:String = Difficulty.getString(PlayState.storyDifficulty, false).toLowerCase();
    _oppDiffAllowed = (diffName == "hard" || diffName == "insane" || diffName == "extreme" || diffName == "godness" || diffName == "true");

    if (optionEnabled) _oppDiffAllowed = true;

    _oppMinHealth = (optionEnabled ? 0.0 : 0.5);
    _oppDrainAmount = 0.015;
    _oppDrainPaused = false;
    _oppDrainCounter = 0;
    _oppResumeThreshold = _oppMinHealth + 0.01;

    var songName:String = "";
    try { songName = PlayState.SONG != null ? PlayState.SONG.song.toLowerCase() : ""; } catch(e:Dynamic) { songName = ""; }
    if (optionEnabled && (songName == "burden" || songName == "remorse" || songName == "evilism"  || songName == "evilism-v1" || songName == "transcendent" || songName == "psychopaty" || songName == "recollaine" || songName == "denkousekka-v1"))
    {
        _oppMinHealth = 0.01;
        _oppResumeThreshold = _oppMinHealth + 0.01;
    }
} catch(e:Dynamic) {
    trace("oppDrain:init error: " + Std.string(e));
}

		Paths.clearUnusedMemory();

		cacheCountdown();
		cachePopUpScore();

		if(eventNotes.length < 1) checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	public function applyBotplayText():Void {
    try {
        if (botplayTxt == null) return;

        botplayTxt.visible = cpuControlled;

var DisableBotplayTexts:Bool = false;


try {
    DisableBotplayTexts = ClientPrefs.data.DisableBotplayTexts;
} catch(e:Dynamic) {
    trace('error while reading DisableBotplayTexts: ' + e);
    DisableBotplayTexts = false;
}

if (DisableBotplayTexts) {
    var _isRusBot:Bool = (ClientPrefs.data.modLanguage == "Rus");
    botplayTxt.text = _isRusBot ? "Ботплей" : "Botplay";
} else {
    var _isRusBot2:Bool = (ClientPrefs.data.modLanguage == "Rus");
    var texts:Array<String>;
    if (_isRusBot2) {
        texts = [
            "это ботплей? да, это так.",
            "не умеешь - научим, не хочешь - заставим",
            "да ты киберспортсмен!",
            "внятного текста тут нет, забей",
            "хз",
            "ОМГ ОМГ ЭТО 1.1.1 SECONDARY!!",
            "Грей Экспанжед нынче недоволен тобой.",
            "ээ.. братан, эта песня очень легкая :/",
            "бот defence edition",
            "ты серьёзно?",
            "геймплей Рустр Экспанжеда...",
            "Меули - подруга Хэндри!",
            "не спрашивай",
            "ха-ха\n какой ты смешной.",
            "П.В.В. Грей скоро прийдёт.",
            "не делай 69%, прошу",
            "ладно. будь так.",
            "лиса в Blender 4.4.1!",
            "у Фи есть кристаллы Криса...",
            "как говорит Тайн: -спасибо, что дали мне собственный голос!",
            "всё ещё злишься?",
            "попробуй другие игры... \n например, Minecraft",
            "Крылья ноги... Ноты!",
            "уа-а",
            "этот текст на 989 строке PlayState,
			а этот на 990",
            "а ты пробовал(-а) это сам(-а) пройти?",
            "47102031",
            "несмешно.",
            "Startup Defencivity: переосмысление",
            "больно.",
            "Compact Engine: БОТПЛЕЙ",
            "НЕ жми на электро-ноты!",
            "Шей умер, кстати.",
            "кто является 3-им творением Элдер Грея?"
        ];
    } else {
        texts = [
            "its botplay. yep, its botplay",
            "autogame",
            "cyber sportsmen",
            "Unknown text here",
            "idk",
            "OMG OMG ITS 1.1.1 SECONDARY!!",
            "Gray Expunged not happy with you.",
            "umm bro its so easy song:/",
            "defence edition bot",
            "ar u serious?",
            "Rooster expunged playing...",
            "Meuly is Handrys friend!",
            "the fuck.",
            "ha-ha\n thats funny.",
            "TT gray will appears",
            "dont make 69%",
            "fine.",
            "fox in Blender 4.4.1!",
            "some Kris Crystals Fi have...",
            "as Tain says: -thanks for giving me the voice",
			"still angry?",
			"try other games... \n e.g. Minecraft",
			"are u armless?",
			"wa-a",
			"This text is on line 1027 of the PlayState code
			and this one is on line 1028",
			"Have you even tried to beat this song yourself?",
			"47102031",
			"ts not funny.",
			"Startup Defencivity Reimagined",
			"that hurts",
			"Compact Engine: BOTPLAY",
			"do NOT click on Electric Notes!",
			"Shay died BTW.",
			"who is 3rd Elder Gray's creation?"
        ];
    }
    var n = texts.length;
    if (n <= 0) botplayTxt.text = (_isRusBot2 ? "ботплей" : "botplay");
    else botplayTxt.text = texts[Std.random(n)];
}

        try {
            if (ClientPrefs.data.downScroll)
                botplayTxt.y = healthBar.y + 70;
            else
                botplayTxt.y = healthBar.y - 90;
        } catch(e:Dynamic) {}

    } catch(e:Dynamic) {
        trace("applyBotplayText error: " + Std.string(e));
    }
}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
	}
	#end

public function reloadHealthBarColors() {
    if (dynamicHealthbarColors && DynamicHealthbarColor.enabled)
    {
        var colors = DynamicHealthbarColor.getCurrentColors();
        if (colors != null)
        {
            healthBar.setColors(colors[0], colors[1]);
            return;
        }
    }

    healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
        FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getSharedPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(Iris.instances.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String):Dynamic
		return variables.get(tag);

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public var videoCutscene:VideoSprite = null;
	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
	{
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile)
		{
			videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
			if(forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong)
			{
				function onVideoEnd()
				{
					if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
					{
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
			else add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	// ── InfectMode: инициализация слоёв заражения ───────────────────────
	function initInfectMode():Void
	{
		infectModeEnabled = ClientPrefs.data.infectMode == true;
		trace('[InfectMode] initInfectMode() infectModeEnabled=' + infectModeEnabled);

		if (!infectModeEnabled) return;

		InfectMode.reset();

		_infectLayer1 = new FlxSprite(0, 0);
		if (Paths.fileExists('images/infect/layer1.png', IMAGE))
			_infectLayer1.loadGraphic(Paths.image('infect/layer1'));
		else
			_infectLayer1.makeGraphic(1280, 720, 0xFF00AA00);
		_infectLayer1.setGraphicSize(FlxG.width, FlxG.height);
		_infectLayer1.updateHitbox();
		_infectLayer1.scrollFactor.set();
		_infectLayer1.cameras = [camHUD];
		_infectLayer1.alpha = 0;

		_infectLayer2 = new FlxSprite(0, 0);
		if (Paths.fileExists('images/infect/layer2.png', IMAGE))
			_infectLayer2.loadGraphic(Paths.image('infect/layer2'));
		else
			_infectLayer2.makeGraphic(1280, 720, 0xFFAA5500);
		_infectLayer2.setGraphicSize(FlxG.width, FlxG.height);
		_infectLayer2.updateHitbox();
		_infectLayer2.scrollFactor.set();
		_infectLayer2.cameras = [camHUD];
		_infectLayer2.alpha = 0;

		_infectLayer3 = new FlxSprite(0, 0);
		if (Paths.fileExists('images/infect/layer3.png', IMAGE))
			_infectLayer3.loadGraphic(Paths.image('infect/layer3'));
		else
			_infectLayer3.makeGraphic(1280, 720, 0xFFAA0000);
		_infectLayer3.setGraphicSize(FlxG.width, FlxG.height);
		_infectLayer3.updateHitbox();
		_infectLayer3.scrollFactor.set();
		_infectLayer3.cameras = [camHUD];
		_infectLayer3.alpha = 0;

		add(_infectLayer1);
		add(_infectLayer2);
		add(_infectLayer3);

		trace('[InfectMode] layer1 exists: ' + Paths.fileExists('images/infect/layer1.png', IMAGE));
		trace('[InfectMode] layer2 exists: ' + Paths.fileExists('images/infect/layer2.png', IMAGE));
		trace('[InfectMode] layer3 exists: ' + Paths.fileExists('images/infect/layer3.png', IMAGE));
		trace('[InfectMode] layers created and added to scene');
	}
	// ────────────────────────────────────────────────────────────────────

	public function startCountdown()
	{
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}
		
		// Проверка читов СРАЗУ при старте
		if (!FairPlayChecker.isFairPlay())
		{
			wasEverUnfair = true;
			trace("Game started UNFAIR! Reasons: " + FairPlayChecker.getUnfairText());
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			canPause = true;
			generateStaticArrows(0);
			generateStaticArrows(1);
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted');

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						// "Ready" — slides in from left with acceleration
						countdownReady = createCountdownSpriteSlide(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						// "Set" — slides in from left with acceleration
						countdownSet = createCountdownSpriteSlide(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						// "Go" — center, bounce scale, then fly up
						countdownGo = createCountdownSpriteGo(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;

	if (MetadataDisplay.enabled && MetadataDisplay.showAtStart) {
        new FlxTimer().start(0.2, function(tmr:FlxTimer) {
            MetadataDisplay.show();
        });
    }
				}

				if(!skipArrowStartTween)
				{
					notes.forEachAlive(function(note:Note) {
						if(ClientPrefs.data.opponentStrums || note.mustPress)
						{
							note.copyAlpha = false;
							note.alpha = note.multAlpha;
							if(ClientPrefs.data.middleScroll && !note.mustPress)
								note.alpha *= 0.35;
						}
						// oppMode middleScroll: боковые ноты BF (mustPress=false) → 35% прозрачность
						else if(opponentPlayMode && ClientPrefs.data.middleScroll && !note.mustPress)
						{
							note.copyAlpha = false;
							note.alpha = note.multAlpha * 0.35;
						}
					});
				}

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	// ── Countdown helpers ────────────────────────────────────────────────────

	// "Ready" / "Set": slide in from left with easing, then fade + slide right fast
	inline private function createCountdownSpriteSlide(image:String, antialias:Bool):FlxSprite
	{
		// Russian variant fallback (e.g. "ready" → "readyRu")
		var imgPath:String = image;
		if (ClientPrefs.data.modLanguage == "Rus")
		{
			var baseName:String = image.contains("/") ? image.split("/").pop() : image;
			var prefix:String  = image.contains("/") ? image.substr(0, image.lastIndexOf("/") + 1) : "";
			var ruPath:String  = prefix + baseName + "Ru";
			if (Paths.fileExists('images/$ruPath.png', IMAGE))
				imgPath = ruPath;
		}

		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(imgPath));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.updateHitbox();
		spr.antialiasing = antialias;

		// Start off-screen to the left, invisible
		spr.screenCenter();
		var centerX:Float = spr.x;
		var centerY:Float = spr.y;
		spr.x = -spr.width - 80;
		spr.alpha = 0;

		insert(members.indexOf(noteGroup), spr);

		// Duration synced to BPM (one beat)
		var beatSec:Float = Conductor.crochet / 1000 / playbackRate;

		// Slide in from left → center
		FlxTween.tween(spr, {x: centerX, alpha: 1}, beatSec * 0.35,
		{
			ease: FlxEase.quadOut
		});

		// After settling, slide off to the right quickly (flip-page feel)
		new FlxTimer().start(beatSec * 0.38, function(_)
		{
			FlxTween.tween(spr, {x: centerX + FlxG.width * 0.6, alpha: 0}, beatSec * 0.62,
			{
				ease: FlxEase.quadIn,
				onComplete: function(_)
				{
					remove(spr);
					spr.destroy();
				}
			});
		});

		return spr;
	}

	// "Go": appears centered, bounces 0.9→1.1→1.0, then flies upward fast
	inline private function createCountdownSpriteGo(image:String, antialias:Bool):FlxSprite
	{
		// Russian variant fallback
		var imgPath:String = image;
		if (ClientPrefs.data.modLanguage == "Rus")
		{
			var baseName:String = image.contains("/") ? image.split("/").pop() : image;
			var prefix:String  = image.contains("/") ? image.substr(0, image.lastIndexOf("/") + 1) : "";
			var ruPath:String  = prefix + baseName + "Ru";
			if (Paths.fileExists('images/$ruPath.png', IMAGE))
				imgPath = ruPath;
		}

		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(imgPath));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.updateHitbox();
		spr.screenCenter();
		spr.antialiasing = antialias;
		spr.alpha = 1;

		// Start at scale 0.9
		spr.scale.set(0.9, 0.9);

		insert(members.indexOf(noteGroup), spr);

		var beatSec:Float = Conductor.crochet / 1000 / playbackRate;

		// Phase 1: 0.9 → 1.1
		FlxTween.tween(spr.scale, {x: 1.1, y: 1.1}, beatSec * 0.18, {ease: FlxEase.quadOut,
			onComplete: function(_)
			{
				// Phase 2: 1.1 → 1.0
				FlxTween.tween(spr.scale, {x: 1.0, y: 1.0}, beatSec * 0.18, {ease: FlxEase.quadIn,
					onComplete: function(_)
					{
						// Phase 3: fly up with fade-out (after a short hold)
						new FlxTimer().start(beatSec * 0.28, function(_)
						{
							spr.acceleration.y = 0;
							FlxTween.tween(spr, {y: spr.y - FlxG.height * 0.55, alpha: 0}, beatSec * 0.55,
							{
								ease: FlxEase.quadIn,
								onComplete: function(_)
								{
									remove(spr);
									spr.destroy();
								}
							});
						});
					}
				});
			}
		});

		return spr;
	}

	// Digit-scramble effect on timeTxt: rapidly flips digits 3 times then shows real time
	private function _startTimeTxtScramble():Void
	{
		if (timeTxt == null || ClientPrefs.data.timeBarType == 'Disabled'
			|| ClientPrefs.data.timeBarType == 'Song Name') return;

		var _scrambleCount:Int = 0;
		var _maxScrambles:Int  = 6; // 3 pairs of digits × 2 flips
		var _interval:Float    = 0.055; // fast but visible

		var timer:FlxTimer = new FlxTimer();
		timer.start(_interval, function(t:FlxTimer)
		{
			_scrambleCount++;
			var m1:Int = FlxG.random.int(0, 9);
			var m2:Int = FlxG.random.int(0, 5);
			var s1:Int = FlxG.random.int(0, 5);
			var s2:Int = FlxG.random.int(0, 9);
			timeTxt.text = '$m1:$m2$s1$s2';

			if (_scrambleCount >= _maxScrambles)
			{
				// Show real current time
				var _curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
				var _songCalc:Float = (songLength > 0) ? (songLength - _curTime) : 0;
				if (ClientPrefs.data.timeBarType == 'Time Elapsed') _songCalc = _curTime;
				var _secs:Int = Std.int(Math.max(0, Math.floor(_songCalc / 1000)));
				timeTxt.text = FlxStringUtil.formatTime(_secs, false);
				t.cancel();
			}
		}, 0); // 0 = repeat forever (we cancel manually)
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				invalidateNote(daNote);
			}
			--i;
		}
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true)
	{
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		updateScoreText();
		if (!miss && !cpuControlled && scoreBop)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

public dynamic function updateScoreText()
{
    var isRus:Bool = (ClientPrefs.data.modLanguage == "Rus");
    var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
    var fcStr:String  = Language.getPhrase(ratingFC);

    if (wasEverUnfair)
    {
        // CHEATING: score and accuracy always show 0, semi-transparent
        scoreTxt.alpha = 0.5;

        var missLabel:String = isRus ? ("Промахи: " + songMisses) : ("Misses: " + songMisses);
        scoreTxt.text = (isRus ? "Счёт: 0" : "Score: 0")
            + "\n" + missLabel
            + "\n" + (isRus ? "Точность: 0%" : "Accuracy: 0%");

        if (cheatNoticeTxt != null)
        {
            var reason:String = FairPlayChecker.getUnfairText();
            cheatNoticeTxt.text    = (isRus ? "Геймплей изменён. " : "Gameplay modified. ") + reason;
            cheatNoticeTxt.visible = !ClientPrefs.data.hideHud;
        }
    }
    else
    {
        scoreTxt.alpha = 1.0;
        if (cheatNoticeTxt != null) cheatNoticeTxt.visible = false;

        if (totalPlayed != 0)
        {
            scoreTxt.text =
                (isRus ? "Счёт: " : "Score: ")    + songScore  + "\n" +
                (isRus ? "Промахи: " : "Misses: ") + songMisses + "\n" +
                (isRus ? "Точность: " : "Accuracy: ") + percent + "% — " + fcStr;
        }
        else
        {
            scoreTxt.text =
                (isRus ? "Счёт: 0" : "Score: 0") + "\n" +
                (isRus ? "Промахи: 0" : "Misses: 0") + "\n" +
                (isRus ? "Точность: —" : "Accuracy: —");
        }
    }
}

private function calculateHealthPercent():Float
{
    // В opponentPlayMode инвертируем: 0% BF = 100% оппонента
    var rawPercent:Float = opponentPlayMode
        ? ((2 - health) / 2) * 100
        : (health / 2) * 100;
    
    if (rawPercent > 100) rawPercent = 100;
    if (rawPercent < 0) rawPercent = 0;
    
    return CoolUtil.floorDecimal(rawPercent, 2);
}

	public dynamic function fullComboFunction()
	{
		var perfects:Int = ratingsData[0].hits;
		var sicks:Int = ratingsData[1].hits;
		var goods:Int = ratingsData[2].hits;
		var oks:Int = ratingsData[3].hits;
		var bads:Int = ratingsData[4].hits;
		var shits:Int = ratingsData[5].hits;

		ratingFC = "";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFC = 'FC';
			else if (oks > 0) ratingFC = 'OFC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
			else if (perfects > 0) ratingFC = 'PFC';
		}
		else {
			if (songMisses < 10) ratingFC = 'SDCB';
			else ratingFC = 'Clear';
		}

		ratingFCCompact = "";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFCCompact = 'FC';
			else if (oks > 0) ratingFCCompact = 'OFC';
			else if (goods > 0) ratingFCCompact = 'GFC';
			else if (sicks > 0) ratingFCCompact = 'SFC';
			else if (perfects > 0) ratingFCCompact = 'PFC';
		}
		else {
			if (songMisses < 10) ratingFCCompact = 'SDCB';
			else ratingFCCompact = 'C';
		}
	}

	public function doScoreBop():Void {
		if(!ClientPrefs.data.scoreZoom)
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float)
	{
		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time - Conductor.offset;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition < vocals.length)
		{
			vocals.time = time - Conductor.offset;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
			vocals.play();
		}
		else vocals.pause();

		if (Conductor.songPosition < opponentVocals.length)
		{
			opponentVocals.time = time - Conductor.offset;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
			opponentVocals.play();
		}
		else opponentVocals.pause();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		// Timebar: fade in + expand from left
		FlxTween.tween(timeBar, {alpha: 1, 'scale.x': 1.0}, 0.65, {ease: FlxEase.quadOut});
		// timeTxt: scramble digits then show real time
		timeTxt.text = "0:00";
		timeTxt.alpha = 0;
		FlxTween.tween(timeTxt, {alpha: 1}, 0.2, {ease: FlxEase.linear,
			onComplete: function(_) {
				_startTimeTxtScramble();
			}
		});

		#if DISCORD_ALLOWED

		if(autoUpdateRPC) DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');

		if (timelessMode && TimelessMode.enabled)
{
    TimelessMode.init(songLength);

    var timelessY = timeBar.y - 15;
    if (ClientPrefs.data.downScroll)
        timelessY = timeBar.y + 15;
    
    TimelessMode.timelessBar = new Bar(0, timelessY, 'timeBar', 
        function() return TimelessMode.getPercentage(), 0, 1);
    TimelessMode.timelessBar.screenCenter(X);
    TimelessMode.timelessBar.scrollFactor.set();
    TimelessMode.timelessBar.visible = !ClientPrefs.data.hideHud;
    TimelessMode.timelessBar.alpha = timeBar.alpha;
    TimelessMode.timelessBar.setColors(FlxColor.CYAN, FlxColor.GRAY);
    TimelessMode.timelessBar.leftToRight = false;
    uiGroup.add(TimelessMode.timelessBar);
    
    // Текст для Timeless
    var timelessTextY = TimelessMode.timelessBar.y - 20;
    TimelessMode.timelessText = new FlxText(0, timelessTextY, 400, "??:??", 16);
    TimelessMode.timelessText.setFormat(Paths.font("vcr.ttf"), 25, FlxColor.WHITE, CENTER, 
        FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
    TimelessMode.timelessText.screenCenter(X);
    TimelessMode.timelessText.scrollFactor.set();
    TimelessMode.timelessText.borderSize = 2;
    TimelessMode.timelessText.visible = !ClientPrefs.data.hideHud;
    uiGroup.add(TimelessMode.timelessText);
}
	}

	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private var totalColumns: Int = 4;

	private function generateSong():Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
try
{
    if (songData.needsVoices && !ClientPrefs.data.gameplaySettings.get('muteVoices'))
    {
        var playerVocals = Paths.voices(songData.song, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
        vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));
        
        var oppVocals = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
        if (oppVocals != null && oppVocals.length > 0) opponentVocals.loadEmbedded(oppVocals);
    }
}
catch (e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try
		{
			inst.loadEmbedded(Paths.inst(songData.song));
		}
		catch (e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		try
		{
			var eventsChart:SwagSong = Song.getChart('events', songName);
			if(eventsChart != null)
				for (event in eventsChart.events) //Event Notes
					for (i in 0...event[1].length)
						makeEvent(event, i);
		}
		catch(e:Dynamic) {}

		var oldNote:Note = null;
		var sectionsData:Array<SwagSection> = PlayState.SONG.notes;
		var ghostNotesCaught:Int = 0;
		var daBpm:Float = Conductor.bpm;
	
		for (section in sectionsData)
		{
			if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			for (i in 0...section.sectionNotes.length)
			{
				final songNotes: Array<Dynamic> = section.sectionNotes[i];
				var spawnTime: Float = songNotes[0];
				var noteColumn: Int = Std.int(songNotes[1] % totalColumns);
				var holdLength: Float = songNotes[2];
				var noteType: String = !Std.isOfType(songNotes[3], String) ? Note.defaultNoteTypes[songNotes[3]] : songNotes[3];
				if (Math.isNaN(holdLength))
					holdLength = 0.0;

				var gottaHitNote:Bool = (songNotes[1] < totalColumns);
				// OpponentPlay: player presses dad strums (0-3)
				var _mustp:Bool = opponentPlayMode ? !gottaHitNote : gottaHitNote;

				if (i != 0) {
					// CLEAR ANY POSSIBLE GHOST NOTES
					for (evilNote in unspawnNotes) {
						// Use _mustp (already flipped for opponentPlayMode) for correct ghost note matching
						var matches: Bool = (noteColumn == evilNote.noteData && _mustp == evilNote.mustPress && evilNote.noteType == noteType);
						if (matches && Math.abs(spawnTime - evilNote.strumTime) < flixel.math.FlxMath.EPSILON) {
							if (evilNote.tail.length > 0)
								for (tail in evilNote.tail)
								{
									tail.destroy();
									unspawnNotes.remove(tail);
								}
							evilNote.destroy();
							unspawnNotes.remove(evilNote);
							ghostNotesCaught++;
							//continue;
						}
					}
				}

				var swagNote:Note = new Note(spawnTime, noteColumn, oldNote);
				var isAlt: Bool = section.altAnim && !gottaHitNote;
				swagNote.gfNote = (section.gfSection && gottaHitNote == section.mustHitSection);
				swagNote.animSuffix = isAlt ? "-alt" : "";
				swagNote.mustPress = _mustp;
				swagNote.sustainLength = holdLength;
				swagNote.noteType = noteType;
	
				swagNote.scrollFactor.set();
				unspawnNotes.push(swagNote);

				var curStepCrochet:Float = 60 / daBpm * 1000 / 4.0;
				final roundSus:Int = Math.round(swagNote.sustainLength / curStepCrochet);
				if(roundSus > 0)
				{
					for (susNote in 0...roundSus)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						var sustainNote:Note = new Note(spawnTime + (curStepCrochet * susNote), noteColumn, oldNote, true);
						sustainNote.animSuffix = swagNote.animSuffix;
						sustainNote.mustPress = swagNote.mustPress;
						sustainNote.gfNote = swagNote.gfNote;
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						swagNote.tail.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if(!PlayState.isPixelStage)
						{
							if(oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
							}

							if(ClientPrefs.data.downScroll)
								sustainNote.correctionOffset = 0;
						}
						else if(oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
						}

						var _susForPlayer:Bool = opponentPlayMode ? gottaHitNote : sustainNote.mustPress;
						if (_susForPlayer) sustainNote.x += FlxG.width / 2; // general offset
						else if(ClientPrefs.data.middleScroll)
						{
							sustainNote.x += 310;
							if(noteColumn > 1) //Up and Right
								sustainNote.x += FlxG.width / 2 + 25;
						}
					}
				}

				// Note X position: mustPress goes right, non-mustPress stays left (or middleScroll shift)
				// In opponentPlayMode the mustPress is already flipped so the standard logic
				// correctly places dad notes (now mustPress) → right, but we want them LEFT.
				// Fix: use the ORIGINAL gottaHitNote (before flip) for position decisions.
				var _posForPlayer:Bool = opponentPlayMode ? gottaHitNote : swagNote.mustPress;
				if (_posForPlayer)
				{
					swagNote.x += FlxG.width / 2; // general offset → right side (BF/player side)
				}
				else if(ClientPrefs.data.middleScroll)
				{
					swagNote.x += 310;
					if(noteColumn > 1) //Up and Right
					{
						swagNote.x += FlxG.width / 2 + 25;
					}
				}
				if(!noteTypes.contains(swagNote.noteType))
					noteTypes.push(swagNote.noteType);

				oldNote = swagNote;
			}
		}
		trace('["${SONG.song.toUpperCase()}" CHART INFO]: Ghost Notes Cleared: $ghostNotesCaught');
		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		unspawnNotes.sort(sortByTime);
		generatedMusic = true;
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				Paths.sound(event.value1); //Precache sound
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true);
		if(returnedValue != null && returnedValue != 0) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
	{
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		for (i in 0...4)
		{
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			// OpponentPlay: player strums (1) are now on the LEFT (no X shift = opp side)
			//               opponent strums (0) are on the RIGHT (player side, always visible)
			if (opponentPlayMode)
			{
				if (player == 1) targetAlpha = 1;   // player controls dad side — always visible
				else             targetAlpha = 1;   // BF side always visible too
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else babyArrow.alpha = targetAlpha;

			if (player == 1)
			{
				// playerStrums: без лишних оффсетов — playerPosition() сама даст нужную позицию
				// oppMode+middleScroll: -278+640=362 (центр) ✓
				// обычный+middleScroll: -278+640=362 (центр) ✓
				playerStrums.add(babyArrow);
			}
			else
			{
				// opponentStrums: middleScroll оффсет всегда (боковые позиции)
				if(ClientPrefs.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) babyArrow.x += FlxG.width / 2 + 25;
				}
				opponentStrums.add(babyArrow);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.playerPosition();

			// oppMode без middleScroll: playerStrums влево, opponentStrums вправо
			// При middleScroll своп не нужен — playerPosition уже даёт центр для playerStrums,
			// а opponentStrums получили боковые через +310/+665
			if (opponentPlayMode && !ClientPrefs.data.middleScroll)
			{
				if (player == 1)
					babyArrow.x -= FlxG.width / 2; // убираем +640 от playerPosition
				else
					babyArrow.x += FlxG.width / 2; // playerPosition ничего не сделала, добавляем
			}
		}
	}

function createHoldSplashes():Void 
{
    if (isPixelStage) return;
    
    var colors:Array<String> = ["Purple", "Blue", "Green", "Red"];
    
    // Индексы 0-3: оппонент, 4-7: игрок
    // Всего 8 слотов
    for (i in 0...8) 
    {
        var colorIndex = i % 4;
        var color = colors[colorIndex];
        
        var splash = new FlxSprite();
        splash.frames = Paths.getSparrowAtlas('HoldNoteEffect/holdCover' + color);
        splash.animation.addByPrefix('hold', 'holdCover' + color, 24, true);
        splash.animation.addByPrefix('end', 'holdCoverEnd' + color, 24, false);
        splash.cameras = [camHUD];
        splash.visible = false;
        splash.antialiasing = ClientPrefs.data.antialiasing;
        
        // Прозрачность синхронизируем с настройкой обычных сплэшей
        var splashAlpha:Float = 1.0;
        try { splashAlpha = ClientPrefs.data.splashAlpha; } catch(e:Dynamic) { splashAlpha = 1.0; }
        splash.alpha = splashAlpha;
        
        noteGroup.add(splash);
        
        holdSplashes.push(splash);
        holdSplashTimers.push(0);
        holdSplashActive.push(false);
    }
}

function showHoldSplash(index:Int):Void 
{
    if (index < 0 || index >= holdSplashes.length) return;
    
    // Индексы 0-3 — оппонент, 4-7 — игрок
    var isOpponent:Bool = (index < 4);
    if (isOpponent) {
        var showOppSplashes:Bool = false;
        try { showOppSplashes = ClientPrefs.data.opponentSplashes; } catch(e:Dynamic) { showOppSplashes = false; }
        if (!showOppSplashes) return;
    }
    
    var splash = holdSplashes[index];
    var strum:StrumNote = isOpponent ? opponentStrums.members[index] : playerStrums.members[index - 4];
    
    // Синхронизируем прозрачность с настройкой нот-сплэшей
    var splashAlpha:Float = 1.0;
    try { splashAlpha = ClientPrefs.data.splashAlpha; } catch(e:Dynamic) { splashAlpha = 1.0; }
    splash.alpha = splashAlpha;
    
    if (strum != null) 
    {
        splash.x = strum.x - 110;
        splash.y = strum.y - 100;
        splash.visible = true;
        
        if (!holdSplashActive[index]) 
        {
            splash.animation.play('hold', true);
            holdSplashActive[index] = true;
        }
        
        holdSplashTimers[index] = Conductor.stepCrochet / 1000;
    }
}

function hideHoldSplash(index:Int):Void 
{
    if (index < 0 || index >= holdSplashes.length) return;
    
    var splash = holdSplashes[index];
    holdSplashActive[index] = false;
    
    // Играем end-анимацию для всех слотов (и игрока, и оппонента)
    if (splash.visible)
    {
        splash.animation.play('end', true);
    } 
    else
    {
        splash.visible = false;
    }
}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = false);
		}

		super.openSubState(SubState);
	}

	public var canResync:Bool = true;
	override function closeSubState()
	{
		super.closeSubState();
		
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong && canResync)
			{
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = true);

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
		}
	}

	#if DISCORD_ALLOWED
	override public function onFocus():Void
	{
		super.onFocus();
		if (!paused && health > 0)
		{
			resetRPC(Conductor.songPosition > 0.0);
		}
	}

	override public function onFocusLost():Void
	{
		super.onFocusLost();
		if (!paused && health > 0 && autoUpdateRPC)
		{
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		}
	}
	#end

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; //performance setting for custom RPC things
	function resetRPC(?showTime:Bool = false)
	{
		#if DISCORD_ALLOWED
		if(!autoUpdateRPC) return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals)
		{
			if (FlxG.sound.music.time < vocals.length)
			{
				voc.time = FlxG.sound.music.time;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			}
			else voc.pause();
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float)
	{

try {
    if (_oppDrainPaused) {
        if (health > _oppResumeThreshold) {
            _oppDrainPaused = false;
            // do not reset counter; keep counting so every 3rd still applies
        }
    }
} catch(e:Dynamic) {
    // ignore
}

if (secondChanceEnabled && SecondChance.enabled && !paused && startedCountdown) {
    SecondChance.update(elapsed);
}

// Fair Play tracking - если стало нечестно, помечаем навсегда
if (!wasEverUnfair && !FairPlayChecker.isFairPlay())
{
    wasEverUnfair = true;
    trace("Game became UNFAIR!");
    trace("Unfair reasons: " + FairPlayChecker.getUnfairText());
}

		if(!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			var idleAnim:Bool = (boyfriend.getAnimationName().startsWith('idle') || boyfriend.getAnimationName().startsWith('danceLeft') || boyfriend.getAnimationName().startsWith('danceRight'));
			if(!startingSong && !endingSong && idleAnim) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		else FlxG.camera.followLerp = 0;
		callOnScripts('onUpdate', [elapsed]);

		if (hardcoreMode && HardcoreMode.enabled && !paused && startedCountdown)
{
    health = HardcoreMode.update(elapsed, health);
}

if (timelessMode && TimelessMode.enabled && !paused && !startingSong && !endingSong)
{
    TimelessMode.update(elapsed);
    
    if (TimelessMode.checkGameOver() && !isDead)
    {
        trace('[Timeless] Time ran out! Game Over.');
        health = 0;
        doDeathCheck();
    }
}

if (dynamicHealthbarColors && DynamicHealthbarColor.enabled && !paused)
{
    var colors = DynamicHealthbarColor.update(elapsed);
    
    if (colors != null)
    {
        healthBar.setColors(colors[0], colors[1]);
    }
}

if (healthLockEnabled && HealthLock.enabled && !paused && startedCountdown) {
    HealthLock.update(elapsed);
}

if (!paused)
{
    visualHealth = FlxMath.lerp(health, visualHealth, Math.exp(-elapsed * smoothHealthSpeed));
    
    if (Math.abs(health - visualHealth) < 0.001)
        visualHealth = health;
}

		super.update(elapsed);

if (ClientPrefs.data.iconBounce == 'Classic' && iconP1 != null && iconP2 != null && healthBar != null)
{

    var lerpSpeed:Float = 1.3;
    iconP1.scale.x = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * lerpSpeed * 10));
    iconP1.scale.y = FlxMath.lerp(1, iconP1.scale.y, Math.exp(-elapsed * lerpSpeed * 10));
    iconP2.scale.x = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * lerpSpeed * 10));
    iconP2.scale.y = FlxMath.lerp(1, iconP2.scale.y, Math.exp(-elapsed * lerpSpeed * 10));

    var baseY:Float = healthBar.y - 75;
    if (ClientPrefs.data.downScroll)
    {
        iconP1.y = baseY + (iconP1.scale.y - 1) * 75;
        iconP2.y = baseY + (iconP2.scale.y - 1) * 75;
    }
    else
    {
        iconP1.y = baseY - (iconP1.scale.y - 1) * 75;
        iconP2.y = baseY - (iconP2.scale.y - 1) * 75;
    }
    
    iconP1.updateHitbox();
    iconP2.updateHitbox();
}

for (i in 0...holdSplashTimers.length) 
{
    if (holdSplashTimers[i] > 0) 
    {
        holdSplashTimers[i] -= elapsed;
        
        if (holdSplashTimers[i] <= 0) 
        {
            hideHoldSplash(i);
        }
    }
    
    var splash = holdSplashes[i];
    if (splash != null && splash.visible && splash.animation.curAnim != null) 
    {
        if (splash.animation.curAnim.name == 'end' && splash.animation.curAnim.finished) 
        {
            splash.visible = false;
        }
    }
}

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		if(botplayTxt != null && botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		// OpponentPlay: fade out grey-blue miss overlay
		// Тинт держится до конца анимации, затем мгновенно сбрасывается
		if (opponentPlayMode && _oppMissTintChar != null && _oppMissOverlayTimer > 0)
		{
			_oppMissOverlayTimer -= elapsed;
			if (_oppMissOverlayTimer <= 0)
			{
				_oppMissOverlayTimer = 0;
				_oppMissTintChar.colorTransform.redMultiplier   = 1;
				_oppMissTintChar.colorTransform.greenMultiplier = 1;
				_oppMissTintChar.colorTransform.blueMultiplier  = 1;
				_oppMissTintChar.dirty = true;
				_oppMissTintChar = null;
			}
		}

		if (controls.PAUSE && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if(!endingSong && !inCutscene && allowDebugKeys)
		{
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (startedCountdown && !paused)
		{
			Conductor.songPosition += elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= Conductor.offset)
			{
				Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-elapsed * 5));
				var timeDiff:Float = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= Conductor.offset)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
{
    if (SONG != null && SONG.song.toLowerCase() == "evilism" && songLength - Conductor.songPosition <= 10000)
    {
        resetInLast10Sec = true;
        trace("RESET in last 10s of Evilism — achieved");
    }
    health = 0;
    trace("RESET = True");
}
		doDeathCheck();

		// ── InfectMode update ────────────────────────────────────────────
		if (infectModeEnabled && !paused && generatedMusic && !_infectedSubStateOpened)
		{
			var fullyInfected:Bool = InfectMode.update(elapsed);

			if (_infectLayer1 != null) _infectLayer1.alpha = InfectMode.layer1;
			if (_infectLayer2 != null) _infectLayer2.alpha = InfectMode.layer2;
			if (_infectLayer3 != null) _infectLayer3.alpha = InfectMode.layer3;

			if (fullyInfected)
			{
				_infectedSubStateOpened = true;
				paused           = true;
				canResync        = false;
				canPause         = false;
				persistentUpdate = false;
				persistentDraw   = true;

				if (FlxG.sound.music != null) FlxG.sound.music.pause();
				if (vocals != null)           vocals.pause();
				if (opponentVocals != null)   opponentVocals.pause();

				openSubState(new InfectedSubState());
			}
		}
		// ── конец InfectMode update ──────────────────────────────────────

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * playbackRate;
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				var randRotate:Bool = false;
var randRotate:Bool = false;
try {
    randRotate = ClientPrefs.data.RandNoteRotate;
} catch(e:Dynamic) {
    randRotate = Reflect.hasField(FlxG.save.data, "RandNoteRotate") ? FlxG.save.data.RandNoteRotate : false;
}
if (randRotate && !dunceNote.isSustainNote) {
    var angles:Array<Float> = [0, 90, 180, 270];
    var newAngle:Float = angles[FlxG.random.int(0, 3)];
    dunceNote.angle = newAngle;
    dunceNote.copyAngle = false;
}
				dunceNote.spawned = true;

				callOnLuas('onSpawnNote', [notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);

				var index:Int = unspawnNotes.indexOf(dunceNote);
				unspawnNotes.splice(index, 1);
			}
		}

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						var i:Int = 0;
						while(i < notes.length)
						{
							var daNote:Note = notes.members[i];
							if(daNote == null) continue;

							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							if(daNote.mustPress)
							{
								// mustPress = player-controlled side
								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
									goodNoteHit(daNote);
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
								opponentNoteHit(daNote);
							else if (opponentPlayMode && !daNote.mustPress && !daNote.blockHit
									&& daNote.canBeHit && !daNote.wasGoodHit && !daNote.ignoreNote
									&& (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
							{
								// OpponentPlay: BF notes (!mustPress) auto-play as CPU
								daNote.wasGoodHit = true;
								opponentNoteHit(daNote);
							}

							if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (daNote.mustPress && !cpuControlled && !daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = daNote.visible = false;
								invalidateNote(daNote);
							}
							if(daNote.exists) i++;
						}
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}
			}
			checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float)
	{
		var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();

		var mult:Float = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();
	}

	public dynamic function updateIconsPosition()
	{
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
	}

var iconsAnimations:Bool = true;
function set_health(value:Float):Float
{
    value = FlxMath.roundDecimal(value, 5); // Fix Float imprecision

    if (secondChanceEnabled && SecondChance.enabled && SecondChance.canTakeDamage() == false) {
        var minHealth:Float = SecondChance.getMinHealth();
        if (value < minHealth) {
            value = minHealth;
        }
    }

    if (healthLockEnabled && HealthLock.enabled) {
        var maxAllowed:Float = HealthLock.getMaxHealth();
        if (value > maxAllowed) {
            value = maxAllowed;
        }
    }
    
    var newHealthPercent:Float = CoolUtil.floorDecimal((value / 2) * 100, 2);
    if(Math.abs(newHealthPercent - lastHealthPercent) >= 0.01)
    {
        lastHealthPercent = newHealthPercent;
        if(scoreTxt != null) updateScoreText();
    }
    
    if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
    {
        health = value;
        visualHealth = value;
        return health;
    }

    // update health bar
    health = value;
    
    var newPercent:Null<Float> = FlxMath.remapToRange(
        FlxMath.bound(visualHealth, healthBar.bounds.min, healthBar.bounds.max), 
        healthBar.bounds.min, healthBar.bounds.max, 0, 100
    );
    healthBar.percent = (newPercent != null ? newPercent : 0);

    iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0;
    iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0;
    
    return health;
}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if(autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		chartingMode = true;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		// OpponentPlay: death triggers when BF hits full HP (health >= 2) = opponent at 0%
		var _deathTrigger:Bool = opponentPlayMode ? (health >= 2.0) : (health <= 0);
		if (((skipHealthCheck && instakillOnMiss) || _deathTrigger) && !practiceMode && !isDead && gameOverTimer == null)
		{

		 if (secondChanceEnabled && SecondChance.enabled && SecondChance.isCharged()) {
            if (SecondChance.tryRevive()) {
                trace('[SecondChance] Player revived! Cancelling death.');
                return false; // Отменяем смерть
            }
        }

			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != LuaUtils.Function_Stop)
			{
				FlxG.animationTimeScale = 1;
				// In opponentPlayMode the player controls dad, so stun the appropriate char
				if (opponentPlayMode) dad.stunned = true;
				else boyfriend.stunned = true;
				deathCounter++;

				paused = true;
				canResync = false;
				canPause = false;
				#if VIDEOS_ALLOWED
				if(videoCutscene != null)
				{
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				FlxG.camera.setFilters([]);

				#if ACHIEVEMENTS_ALLOWED
if (resetInLast10Sec)
{
    Achievements.unlock("true_genius");
    resetInLast10Sec = false;
}
#end

				if(GameOverSubstate.deathDelay > 0)
				{
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
					{
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						openSubState(new GameOverSubstate(opponentPlayMode ? dad : boyfriend));
						gameOverTimer = null;
					});
				}
				else
				{
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
					openSubState(new GameOverSubstate(opponentPlayMode ? dad : boyfriend));
				}

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if(autoUpdateRPC) DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

case 'Show Metadata':
    var customAuthor:String = value1 != null && value1.trim().length > 0 ? value1 : null;
    var customExtra:String = value2 != null && value2.trim().length > 0 ? value2 : null;
    
    if (MetadataDisplay.enabled) {
        MetadataDisplay.show(customAuthor, customExtra);
    }

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							boyfriend = boyfriendMap.get(value2);
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						if (dynamicHealthbarColors && DynamicHealthbarColor.enabled)
						{
							var oppColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
							var plyColor = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
							DynamicHealthbarColor.checkCharacters(dad.curCharacter, boyfriend.curCharacter, oppColor, plyColor);
							lastPlayerChar = boyfriend.curCharacter;
						}
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if(dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							dad = dadMap.get(value2);
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						if (dynamicHealthbarColors && DynamicHealthbarColor.enabled)
						{
							var oppColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
							var plyColor = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
							DynamicHealthbarColor.checkCharacters(dad.curCharacter, boyfriend.curCharacter, oppColor, plyColor);
							lastOpponentChar = dad.curCharacter;
						}
						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}

				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var trueValue:Dynamic = value2.trim();
					if (trueValue == 'true' || trueValue == 'false') trueValue = trueValue == 'true';
					else if (flValue2 != null) trueValue = flValue2;
					else trueValue = value2;

					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], trueValue);
					} else {
						LuaUtils.setVarInArray(this, value1, trueValue);
					}
				}
				catch(e:Dynamic)
				{
					var len:Int = e.message.indexOf('\n') + 1;
					if(len <= 0) len = e.message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			moveCameraToGirlfriend();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		// OpponentPlay: camera follows dad when it's the "player's turn" = opponent's section
		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		if (isDad)
			callOnScripts('onMoveCamera', ['dad']);
		else
			callOnScripts('onMoveCamera', ['boyfriend']);
	}
	
	public function moveCameraToGirlfriend()
	{
		camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
		camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
		camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
		tweenCamIn();
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			if(dad == null) return;
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			if(boyfriend == null) return;
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();
		resetInLast10Sec = false;

		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		//Should kill you if you tried to cheat
		if(!startingSong)
		{
			notes.forEachAlive(function(daNote:Note)
			{
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			});
			for (daNote in unspawnNotes)
			{
				if(daNote != null && daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		if (hardcoreMode) HardcoreMode.reset();
if (timelessMode) TimelessMode.reset();

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie' #if BASE_GAME_FILES, 'debugger' #end]);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != LuaUtils.Function_Stop && !transitioning)
		{
			#if !switch
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			
if (!cpuControlled && !practiceMode)
{
	if (opponentPlayMode)
	{
		// Save as opponent score under a separate key: "opp_<songName>"
		var oppKey:String = 'opp_' + Song.loadedSongName;
		Highscore.saveScore(oppKey, opponentSongScore, storyDifficulty, percent);
		opponentRatingPercent = percent;
	}
	else
	{
		Highscore.saveScore(Song.loadedSongName, songScore, storyDifficulty, percent);
		
		var fcType:String = calculateFCType();
		Highscore.saveFCType(Song.loadedSongName, storyDifficulty, fcType);
		
		var sickCount:Int = ratingsData[1].hits;
		Highscore.saveSickCount(Song.loadedSongName, storyDifficulty, sickCount);
	}
}

var fcType:String = calculateFCType();
Highscore.saveFCType(Song.loadedSongName, storyDifficulty, fcType);

var sickCount:Int = (cpuControlled || practiceMode) ? -1 : ratingsData[1].hits;
Highscore.saveSickCount(Song.loadedSongName, storyDifficulty, sickCount);
var songKey:String = Paths.formatToSongPath(Song.loadedSongName).toLowerCase();

var accPct:Int = 0;
if (!Math.isNaN(percent)) {
    if (percent > 1) accPct = Std.int(percent + 0.5); else accPct = Std.int(percent * 100 + 0.5);
}

var diffName:String = Difficulty.getString(storyDifficulty, false).toLowerCase();

trace('ACHIEVEMENT SONG CHECK -> song: ' + songKey + ' acc:' + accPct + ' diff:' + diffName);

if (songKey == "memory_test" && accPct >= 90 && (diffName == "normal" || diffName == "hard")) {
    trace('Unlock candidate: nice_enough');
    Achievements.unlock("nice_enough");
}

if (songKey == "silence" && accPct >= 95) {
    trace('Unlock candidate: he_continues_silent');
    Achievements.unlock("he_continues_silent");
}

if (songKey == "mrpig" && accPct == 0 && cpuControlled == false) {
    trace('Unlock candidate: true_zero');
    Achievements.unlock("true_zero");
}

if (songKey == "graduate_work" && cpuControlled == false) {
    trace('Unlock candidate: exam');
    Achievements.unlock("exam");
}

if (songKey == "gunpatsuseizutsu" && cpuControlled == false) {
    trace('Unlock candidate: clasterheadache');
    Achievements.unlock("clasterheadache");
}

if (songKey == "evilism" && accPct < 40) {
    trace('Unlock candidate: by_a_thread');
    Achievements.unlock("by_a_thread");
}

if (songKey == "tranquil_story" && accPct >= 95 && diffName == "hard") {
    trace('Unlock candidate: fox_lover');
    Achievements.unlock("fox_lover");
}
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{

				var canSave:Bool = !wasEverUnfair && !chartingMode;

				// При читах всегда добавляем 0 к campaign score
				campaignScore += (wasEverUnfair ? 0 : songScore);
				campaignMisses += songMisses; // Misses всегда реальные
				campaignTotalPlayed += totalPlayed;
				campaignNotesHit    += totalNotesHit;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music(ClientPrefs.data.mainMenuMusic), 1);
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					canResync = false;
		if (isWelcomeTutorial && storyWeek == 0)
		{
		    isWelcomeTutorial = false;
    		FlxG.save.data.hasSeenWelEnding = true;
    		FlxG.save.flush();
    		states.WelEndingState.weekAccuracy = campaignTotalPlayed > 0
    			? (campaignNotesHit / campaignTotalPlayed) * 100
    			: 0;
    		MusicBeatState.switchState(new states.WelEndingState());
		}
		else
		{
		    MusicBeatState.switchState(new StoryMenuState());
		}

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
if (canSave)
{
    Highscore.saveWeekScore(WeekData.weeksList[storyWeek], campaignScore, storyDifficulty);
if (isStoryMode && storyPlaylist.length <= 0)
{
    var diff:String = Difficulty.getString(PlayState.storyDifficulty).toLowerCase().trim();
    var totalScore:Int = campaignScore;

    // Проверка ачивок по ID недели
    switch (storyWeekID)
    {
        case "week1":
            if ((diff == "hard" || diff == "insane") && totalScore >= 275000)
                Achievements.unlock('ready_for_work_and_defense');

        case "week2":
            if ((diff == "hard" || diff == "insane") && totalScore >= 385000)
                Achievements.unlock('twisted');

        case "week3":
            if ((diff == "insane" || diff == "extreme") && totalScore >= 350000)
                Achievements.unlock('something_wrong');

        case "week4":
            if ((diff == "possible" || diff == "true") && totalScore >= 675000)
                Achievements.unlock('savior');

            if (diff == "true" && totalScore >= 813000)
                Achievements.unlock('are_you_okay');

        case "week5":
            if (diff == "hard" && totalScore >= 500000)
                Achievements.unlock('Yureikosfanbase');

    }
    storyWeekID = "";
}
    trace("Week score saved: " + campaignScore);
}
else
{
    trace("Week score NOT saved - Unfair gameplay: " + FairPlayChecker.getUnfairText());
}

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					canResync = false;
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState(), false, false);
				}
			}
			else
			{

				var canSave:Bool = !wasEverUnfair && !chartingMode;

if (canSave)
{
    Highscore.saveScore(SONG.song, songScore, storyDifficulty);
    trace("Score saved: " + songScore);
}
else
{
    trace("Score NOT saved - Game was unfair.");
    trace("Unfair reasons: " + FairPlayChecker.getUnfairText());
}

				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				canResync = false;
				MusicBeatState.switchState(new FreeplayState());
				FlxG.sound.playMusic(Paths.music(ClientPrefs.data.mainMenuMusic), 1);
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

public function calculateFCType():String
{
	if (cpuControlled || practiceMode)
		return "";
	
	var perfects:Int = ratingsData[0].hits;
	var sicks:Int = ratingsData[1].hits;
	var goods:Int = ratingsData[2].hits;
	var oks:Int = ratingsData[3].hits;
	var bads:Int = ratingsData[4].hits;
	var shits:Int = ratingsData[5].hits;

	if (songMisses == 0)
	{
		if (sicks == 0 && goods == 0 && oks == 0 && bads == 0 && shits == 0)
			return "PFC";

		if (sicks > 0 && goods == 0 && oks == 0 && bads == 0 && shits == 0)
			return "SFC";

		if (goods > 0 && oks == 0 && bads == 0 && shits == 0)
			return "GFC";

		if (oks > 0 && bads == 0 && shits == 0)
			return "OFC";

		return "FC";
	}
	
	// Есть промахи
	if (songMisses < 10)
		return "SDCB"; // 1-9 промахов
	
	return "C"; // 10+ промахов
}

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;
			invalidateNote(daNote);
		}
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore()
	{
		var uiFolder:String = "";
		if (stageUI != "normal")
			uiFolder = uiPrefix + "UI/";

		for (rating in ratingsData)
			Paths.image(uiFolder + rating.image + uiPostfix);
		for (i in 0...10)
			Paths.image(uiFolder + 'num' + i + uiPostfix);
	}

	private function popUpScore(note:Note = null):Void
	{
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0)
		{
			for (spr in comboGroup)
			{
				if(spr == null) continue;

				comboGroup.remove(spr);
				spr.destroy();
			}
		}

		var placement:Float = FlxG.width * 0.35;
		var rating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);

		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if (healthLockEnabled && HealthLock.enabled && !note.ratingDisabled) {
    HealthLock.onNoteHit(daRating.name.toLowerCase());
}

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		if(!cpuControlled) {
			// Начисляем очки ТОЛЬКО если игра честная
			if (!wasEverUnfair) songScore += score;
			if(!note.ratingDisabled)
			{
				songHits++;
				totalPlayed++;
				RecalculateRating(false);
			}
		}

		if (secondChanceEnabled && SecondChance.enabled && !note.ratingDisabled) {
    SecondChance.onNoteHit(daRating.name.toLowerCase());
}

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal")
		{
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		// Use Russian rating sprite variant when modLanguage == "Rus" (e.g. SickRu, GoodRu…)
		var _ratingImg:String = daRating.image;
		if (uiFolder == "" && uiPostfix == "" && ClientPrefs.data.modLanguage == "Rus")
		{
			var _rusVariant:String = _ratingImg + "Ru";
			if (Paths.fileExists('images/$_rusVariant.png', IMAGE))
				_ratingImg = _rusVariant;
		}
		rating.loadGraphic(Paths.image(uiFolder + _ratingImg + uiPostfix));
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * playbackRate * playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.x += ClientPrefs.data.comboOffset[0];
		rating.y -= ClientPrefs.data.comboOffset[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'combo' + uiPostfix));
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
		comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
		comboSpr.x += ClientPrefs.data.comboOffset[0];
		comboSpr.y -= ClientPrefs.data.comboOffset[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
		comboGroup.add(rating);

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
			comboGroup.add(comboSpr);

		var separatedScore:String = Std.string(combo).lpad('0', 3);
		for (i in 0...separatedScore.length)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + uiPostfix));
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + ClientPrefs.data.comboOffset[2];
			numScore.y += 80 - ClientPrefs.data.comboOffset[3];

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		comboSpr.x = xThing + 50;
		FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
			startDelay: Conductor.crochet * 0.001 / playbackRate
		});

		FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
			onComplete: function(tween:FlxTween)
			{
				comboSpr.destroy();
				rating.destroy();
			},
			startDelay: Conductor.crochet * 0.002 / playbackRate
		});
	}

	public function popUpOpponentCombo():Void
	{
		// Проверяем настройку
		var showOppCombo:Bool = false;
		try { showOppCombo = ClientPrefs.data.opponentCombo; } catch(e:Dynamic) {}
		if (!showOppCombo || ClientPrefs.data.hideHud) return;

		// Получаем offset (4 значения: ratingX, ratingY, numX, numY)
		var oppOffset:Array<Int> = [0, 0, 0, 0];
		try {
			var raw = ClientPrefs.data.opponentComboOffset;
			if (raw != null && raw.length >= 4) oppOffset = raw;
		} catch(e:Dynamic) {}

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal")
		{
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		var placement:Float = FlxG.width * 0.10;

		// Очищаем если comboStacking выключен
		if (!ClientPrefs.data.comboStacking && opponentComboGroup.members.length > 0)
		{
			for (spr in opponentComboGroup)
			{
				if (spr == null) continue;
				opponentComboGroup.remove(spr);
				spr.destroy();
			}
		}

		// Rating спрайт (не показываем рейтинг оппонента — только цифры комбо)
		// Показываем только числа комбо
		var separatedScore:String = Std.string(opponentCombo).lpad('0', 3);
		var daLoop:Int = 0;
		var xThing:Float = 0;
		for (i in 0...separatedScore.length)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + uiPostfix));
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + oppOffset[2];
			numScore.y += 80 - oppOffset[3];

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.antialiasing = antialias;
			opponentComboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween) { numScore.destroy(); },
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if (numScore.x > xThing) xThing = numScore.x;
		}
	}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);

		if (!controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
		}
	}

	private function keyPressed(key:Int)
	{
		// In opponentPlayMode the player controls dad, so stun check uses dad
		var _isStunned:Bool = opponentPlayMode ? dad.stunned : boyfriend.stunned;
		if(cpuControlled || paused || inCutscene || key < 0 || key >= playerStrums.length || !generatedMusic || endingSong || _isStunned) return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// more accurate hit time for the ratings?
		var lastTime:Float = Conductor.songPosition;
		if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		// obtain notes that the player can hit
		var plrInputNotes:Array<Note> = notes.members.filter(function(n:Note):Bool {
			var canHit:Bool = n != null && !strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit;
			return canHit && !n.isSustainNote && n.noteData == key;
		});
		plrInputNotes.sort(sortHitNotes);

		if (plrInputNotes.length != 0) { // slightly faster than doing `> 0` lol
			var funnyNote:Note = plrInputNotes[0]; // front note

			if (plrInputNotes.length > 1) {
				var doubleNote:Note = plrInputNotes[1];

				if (doubleNote.noteData == funnyNote.noteData) {
					// if the note has a 0ms distance (is on top of the current note), kill it
					if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
						invalidateNote(doubleNote);
					else if (doubleNote.strumTime < funnyNote.strumTime)
					{
						// replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
						funnyNote = doubleNote;
					}
				}
			}
			goodNoteHit(funnyNote);
		}
		else
		{
			if (ClientPrefs.data.ghostTapping)
				callOnScripts('onGhostTap', [key]);
			else
				noteMissPress(key);
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario
		if(!keysPressed.contains(key)) keysPressed.push(key);

		//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
		Conductor.songPosition = lastTime;

		var spr:StrumNote = playerStrums.members[key];
		if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyPress', [key]);
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(cpuControlled || !startedCountdown || paused || key < 0 || key >= playerStrums.length) return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		var spr:StrumNote = playerStrums.members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyRelease', [key]);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in keysArray)
		{
			holdArray.push(controls.pressed(key));
			pressArray.push(controls.justPressed(key));
			releaseArray.push(controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		var _keysStunned:Bool = opponentPlayMode ? dad.stunned : boyfriend.stunned;
		if (startedCountdown && !inCutscene && !_keysStunned && generatedMusic)
		{
			if (notes.length > 0) {
				for (n in notes) { // I can't do a filter here, that's kinda awesome
					var canHit:Bool = (n != null && !strumsBlocked[n.noteData] && n.canBeHit
						&& n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

					if (guitarHeroSustains)
						canHit = canHit && n.parent != null && n.parent.wasGoodHit;

					if (canHit && n.isSustainNote) {
						var released:Bool = !holdArray[n.noteData];

						if (!released)
							goodNoteHit(n);
					}
				}
			}

			if (!holdArray.contains(true) || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1)
				invalidateNote(note);
		});

		    if (healthLockEnabled && HealthLock.enabled) {
        HealthLock.onMiss();
    }

    noteMissCommon(daNote.noteData, daNote);

		stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.data.ghostTapping) return; //fuck it

		    if (healthLockEnabled && HealthLock.enabled) {
        HealthLock.onMiss();
    }

    noteMissCommon(direction);

		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
		callOnScripts('noteMissPress', [direction]);
		if (!ClientPrefs.data.ghostTapping)
{
    if (hardcoreMode && HardcoreMode.enabled)
    {
        HardcoreMode.onMiss();
    }
    
    if (timelessMode && TimelessMode.enabled)
    {
        TimelessMode.onMiss();
    }
}
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// score and data
		var subtract:Float = pressMissDamage;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && guitarHeroSustains && note.parent == null) {
			if(note.tail.length > 0) {
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				subtract *= note.tail.length + 1;
			}

			if (note.missed)
				return;
		}
		if (note != null && guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && parentNote.tail.length > 0) {
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if (hardcoreMode && HardcoreMode.enabled)
{
    HardcoreMode.onMiss();
}

if (timelessMode && TimelessMode.enabled)
{
    TimelessMode.onMiss();
}

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		// ── InfectMode: пропуск = заражение, урон HP вдвое меньше ───────
		trace('[InfectMode] noteMissCommon: infectModeEnabled=' + infectModeEnabled + ' note=' + (note != null ? note.noteType + ' isSustain=' + note.isSustainNote : 'null'));
		if (infectModeEnabled && (note == null || !note.isSustainNote))
		{
			InfectMode.onInfectNoteHit();
			subtract *= 0.5;
			trace('[InfectMode] miss triggered → layer1=' + InfectMode.layer1 + ' layer2=' + InfectMode.layer2 + ' layer3=' + InfectMode.layer3);
		}
		// ────────────────────────────────────────────────────────────────

		// OpponentPlay: miss = BF gains health (bad for opponent player)
		if (opponentPlayMode)
			health += subtract * healthLoss;
		else
			health -= subtract * healthLoss;

		// Score tracking
		songScore -= 10;
		if(!endingSong) songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		if (opponentPlayMode)
		{
			// OpponentPlay miss: animate dad
			var char:Character = dad;
			if ((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

			if (char != null && (note == null || !note.noMissAnimation))
			{
				var postfix:String = (note != null) ? note.animSuffix : '';
				var missAnim:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + postfix;
				if (char.hasMissAnimations)
				{
					char.playAnim(missAnim, true);
				}
				else
				{
					// Нет мисс-анимации: хит-анимация + colorTransform (только непрозрачные пиксели)
					var hitAnim:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + postfix;
					if (char.hasAnimation(hitAnim)) char.playAnim(hitAnim, true);
					char.colorTransform.redMultiplier   = 0.55;
					char.colorTransform.greenMultiplier = 0.65;
					char.colorTransform.blueMultiplier  = 0.95;
					char.dirty = true;
					// Держать тинт до конца анимации
					var animDur:Float = 0.35;
					try {
						var curAnim = char.animation.curAnim;
						if (curAnim != null && curAnim.frames != null && curAnim.frameRate > 0)
							animDur = curAnim.frames.length / curAnim.frameRate;
					} catch(_e:Dynamic) {}
					_oppMissOverlayTimer = animDur;
					_oppMissTintChar = char;
				}
			}
			vocals.volume = 0;
		}
		else
		{
			var char:Character = boyfriend;
			if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

			if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
			{
				var postfix:String = '';
				if(note != null) postfix = note.animSuffix;

				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + postfix;
				char.playAnim(animToPlay, true);

				if(char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad'))
				{
					gf.playAnim('sad');
					gf.specialAnim = true;
				}
			}
			vocals.volume = 0;
		}
	}

	function opponentNoteHit(note:Note):Void
	{
		var result:Dynamic = callOnLuas('opponentNoteHitPre', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript('opponentNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		if (songName != 'tutorial')
			camZooming = true;

		// OpponentPlay: BF is CPU opponent now → animate boyfriend on opponentNoteHit
		var _oppNoteChar:Character = opponentPlayMode ? boyfriend : dad;
		if(note.noteType == 'Hey!' && _oppNoteChar.hasAnimation('hey'))
		{
			_oppNoteChar.playAnim('hey', true);
			_oppNoteChar.specialAnim = true;
			_oppNoteChar.heyTimer = 0.6;
		}
		else if(!note.noAnimation)
		{
			var char:Character = _oppNoteChar;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + note.animSuffix;
			if(note.gfNote) char = gf;

			if(char != null)
			{
				var canPlay:Bool = true;
				if(note.isSustainNote)
				{
					var holdAnim:String = animToPlay + '-hold';
					if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
					if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
				}

				if(canPlay) char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if(opponentVocals.length <= 0) vocals.volume = 1;
		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;

		// Hold splash для оппонента (индексы 0-3)
		if (!isPixelStage)
		{
			if (note.isSustainNote)
				showHoldSplash(Std.int(Math.abs(note.noteData))); // 0-3
			else
			{
				// Note splash для оппонента — только если opponentSplashes включены
				var showOppSplashes:Bool = false;
				try { showOppSplashes = ClientPrefs.data.opponentSplashes; } catch(e:Dynamic) {}
				if (showOppSplashes && !note.noteSplashData.disabled)
				{
					var strum:StrumNote = opponentStrums.members[note.noteData];
					if (strum != null)
					{
						var splashAlpha:Float = 1.0;
						try { splashAlpha = ClientPrefs.data.splashAlpha; } catch(e:Dynamic) {}
						var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
						splash.babyArrow = strum;
						splash.spawnSplashNote(strum.x, strum.y, note.noteData, note);
						splash.alpha = splashAlpha;
						grpNoteSplashes.add(splash);
					}
				}
			}
		}

		stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note));
		var result:Dynamic = callOnLuas('opponentNoteHit', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHit', [note]);

		if (!note.isSustainNote)
		{
			// Увеличиваем комбо оппонента только за целые ноты (не сустейн-части)
			opponentCombo++;
			if (opponentCombo > 999999) opponentCombo = 999999;
			popUpOpponentCombo();
			invalidateNote(note);
		}

try {
    // check gating: paused or not allowed by difficulty/option
    if (_oppDrainPaused) {
        // do nothing while paused
    } else if (!_oppDiffAllowed) {
        // not allowed on this difficulty and option not enabled
    } else {
        // If old input system (guitarHeroSustains) is OFF, sustain pieces don't count as notes for damage
        // Just like the player doesn't score on sustain pieces when guitarHeroSustains is off
        var isSustainDamageAllowed:Bool = (!note.isSustainNote) || guitarHeroSustains;
        if (!isSustainDamageAllowed) {
            // skip: sustain note but old input system is off — no damage for sustain pieces
        } else if (!HealthLock.shouldBlockOpponentDamage(-_oppDrainAmount)) {
            // HealthLock enabled → opponent damage is fully blocked
            var optionEnabled:Bool = false;
            try { optionEnabled = ClientPrefs.data.opponentCanKill; } catch(e:Dynamic) {
                try { optionEnabled = ClientPrefs.data.gameplaySettings.get('opponentCanKill'); } catch(e:Dynamic) { optionEnabled = false; }
            }

            if (optionEnabled) {
                _oppDrainCounter++;
                if ((_oppDrainCounter % 3) == 0) {
                    var hp:Float = health;
                    if (hp > _oppMinHealth) {
                        var newHp:Float = hp - _oppDrainAmount;
                        if (newHp < _oppMinHealth) newHp = _oppMinHealth;
                        health = newHp;
                    }
                    if (health <= _oppMinHealth) _oppDrainPaused = true;
                }
            } else {
                var hp2:Float = health;
                if (hp2 > _oppMinHealth) {
                    var newHp2:Float = hp2 - _oppDrainAmount;
                    if (newHp2 < _oppMinHealth) newHp2 = _oppMinHealth;
                    health = newHp2;
                }
                if (health <= _oppMinHealth) _oppDrainPaused = true;
            }
        }
    }
} catch(e:Dynamic) {
    trace("oppDrain:opponentNoteHit error: " + Std.string(e));
}

	}

	public function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(cpuControlled && note.ignoreNote) return;

		// ── InfectMode: нажатие инфект-ноты = обычное нажатие, заражения нет ──
		// Заражение происходит только при ПРОПУСКЕ (см. noteMiss)
		// ────────────────────────────────────────────────────────────────────

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var result:Dynamic = callOnLuas('goodNoteHitPre', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript('goodNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		note.wasGoodHit = true;

		if (note.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), note.hitsoundVolume);

		if(!note.hitCausesMiss) //Common notes
		{
			if(!note.noAnimation)
			{
				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + note.animSuffix;

				// OpponentPlay: player controls dad, so goodNoteHit animates dad
				var char:Character = opponentPlayMode ? dad : boyfriend;
				var animCheck:String = opponentPlayMode ? 'hey' : 'hey';
				if (note.isSustainNote && !isPixelStage)
{
    var splashIndex = opponentPlayMode ? note.noteData : note.noteData + 4;
    showHoldSplash(splashIndex);
}
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}

				if(char != null)
				{
					var canPlay:Bool = true;
					if(note.isSustainNote)
					{
						var holdAnim:String = animToPlay + '-hold';
						if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
						if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
					}
	
					if(canPlay) char.playAnim(animToPlay, true);
					char.holdTimer = 0;

					if(note.noteType == 'Hey!')
					{
						if(char.hasAnimation(animCheck))
						{
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
			}

			if(!cpuControlled)
			{
				var spr = playerStrums.members[note.noteData];
				if(spr != null) spr.playAnim('confirm', true);
			}
			else strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			vocals.volume = 1;

			if (!note.isSustainNote)
			{
				combo++;
				if(combo > 999999) combo = 999999;
				popUpScore(note);
			}
			var gainHealth:Bool = true;
			if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
			if (gainHealth)
			{
				// OpponentPlay: hitting a note LOWERS BF health (gains for opponent = loses for BF)
				if (opponentPlayMode)
					health -= note.hitHealth * healthGain;
				else
					health += note.hitHealth * healthGain;
			}

		}
		else //Notes that count as a miss if you hit them (Hurt notes for example)
		{
			if(!note.noMissAnimation)
			{
				switch(note.noteType)
				{
					case 'Hurt Note':
						if(boyfriend.hasAnimation('hurt'))
						{
							boyfriend.playAnim('hurt', true);
							boyfriend.specialAnim = true;
						}
				}
			}

			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote) spawnNoteSplashOnNote(note);
		}

		stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note));
		var result:Dynamic = callOnLuas('goodNoteHit', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHit', [note]);
		if(!note.isSustainNote) invalidateNote(note);
	}

	public function invalidateNote(note:Note):Void {
		note.kill();
		notes.remove(note, true);
		note.destroy();
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note, strum);
		}
	}

	public function spawnNoteSplash(x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:StrumNote) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		if (psychlua.CustomSubstate.instance != null)
		{
			closeSubState();
			resetSubState();
		}

		#if LUA_ALLOWED
		for (lua in luaArray)
		{
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = null;
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				if(script.exists('onDestroy')) script.call('onDestroy');
				script.destroy();
			}

		hscriptArray = null;
		#end
		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if(videoCutscene != null)
		{
			videoCutscene.destroy();
			videoCutscene = null;
		}
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.setFilters([]);

		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		FlxG.animationTimeScale = 1;

		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		// OpponentPlay overlay cleanup
		if (_oppMissOverlay != null) { remove(_oppMissOverlay); _oppMissOverlay = null; }

		NoteSplash.configs.clear();
		instance = null;

if (infoText != null) {
    infoText.destroy();
    infoText = null;
	resetInLast10Sec = false;
}

HardcoreMode.reset();
TimelessMode.reset();
DynamicHealthbarColor.reset();
HealthLock.reset();
SecondChance.reset();
MetadataDisplay.reset();

if (holdSplashes != null)
{
    for (splash in holdSplashes)
        if (splash != null)
            splash.destroy();
    holdSplashes = null;
}
holdSplashTimers = null;
holdSplashActive = null;

		super.destroy();
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

override function beatHit()
{
    if(lastBeatHit >= curBeat) {
        return;
    }

    if (generatedMusic)
        notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

    // Проверяем опцию IconBounceatHP
    var useHPMultiplier:Bool = false;
    try {
        useHPMultiplier = ClientPrefs.data.IconBounceatHP;
    } catch(e:Dynamic) {
        useHPMultiplier = false;
    }

    var healthPercent:Float = health / 2; // 0 до 1
    var p1Mult:Float = 1.0;
    var p2Mult:Float = 1.0;
    
    if (useHPMultiplier && healthBar != null)
    {
        p1Mult = 0.5 + healthPercent;
        p2Mult = 1.5 - healthPercent;
    }

    switch(ClientPrefs.data.iconBounce)
    {
        case 'Classic':
            var targetP1:Float = 1.2 * p1Mult;
            var targetP2:Float = 1.2 * p2Mult;
            
            iconP1.scale.set(targetP1, targetP1);
            iconP2.scale.set(targetP2, targetP2);
            iconP1.updateHitbox();
            iconP2.updateHitbox();

        case 'Psych':
            var scaleP1:Float = 1.2 * p1Mult;
            var scaleP2:Float = 1.2 * p2Mult;
            
            iconP1.scale.set(scaleP1, scaleP1);
            iconP2.scale.set(scaleP2, scaleP2);
            iconP1.updateHitbox();
            iconP2.updateHitbox();

        case 'Inverted Psych':

            FlxTween.cancelTweensOf(iconP1.scale);
            FlxTween.cancelTweensOf(iconP2.scale);
            
            var targetP1:Float = 1.2 * p1Mult;
            var targetP2:Float = 1.2 * p2Mult;
            
            // Моментально сбрасываем на 1.0
            iconP1.scale.set(1, 1);
            iconP2.scale.set(1, 1);
            iconP1.updateHitbox();
            iconP2.updateHitbox();
            
            // Плавно увеличиваем с EaseIn (ускорение в конце)
            var beatDuration:Float = Conductor.crochet / 1000;
            FlxTween.tween(iconP1.scale, {x: targetP1, y: targetP1}, beatDuration, {
                ease: FlxEase.cubeIn,
                onComplete: function(twn:FlxTween) {
                    // Моментальный reset после достижения максимума
                    iconP1.scale.set(1, 1);
                    iconP1.updateHitbox();
                }
            });
            FlxTween.tween(iconP2.scale, {x: targetP2, y: targetP2}, beatDuration, {
                ease: FlxEase.cubeIn,
                onComplete: function(twn:FlxTween) {
                    iconP2.scale.set(1, 1);
                    iconP2.updateHitbox();
                }
            });

        case 'SDefence':
            FlxTween.cancelTweensOf(iconP1);
            FlxTween.cancelTweensOf(iconP1.scale);
            FlxTween.cancelTweensOf(iconP2);
            FlxTween.cancelTweensOf(iconP2.scale);

            var tweenTime:Float = 0.1;
            
            // Углы и scale с множителем HP от 50%
            var angleP1:Float = 10 * p1Mult; // 10-30 градусов
            var angleP2:Float = 10 * p2Mult;
            var scaleP1:Float = 1 + (0.2 * p1Mult); // 1.1 - 1.3
            var scaleP2:Float = 1 + (0.2 * p2Mult);
            
            if (curBeat % 2 == 0)
            {
                iconP1.angle = -angleP1;
                iconP2.angle = angleP2;
            }
            else
            {
                iconP1.angle = angleP1;
                iconP2.angle = -angleP2;
            }
            
            iconP1.scale.set(scaleP1, scaleP1);
            iconP2.scale.set(scaleP2, scaleP2);
            iconP1.updateHitbox();
            iconP2.updateHitbox();

            FlxTween.tween(iconP1, {angle: 0}, tweenTime, {ease: FlxEase.linear});
            FlxTween.tween(iconP2, {angle: 0}, tweenTime, {ease: FlxEase.linear});
            FlxTween.tween(iconP1.scale, {x: 1, y: 1}, tweenTime, {ease: FlxEase.linear});
            FlxTween.tween(iconP2.scale, {x: 1, y: 1}, tweenTime, {ease: FlxEase.linear});

        case 'Push':
            FlxTween.cancelTweensOf(iconP1.scale);
            FlxTween.cancelTweensOf(iconP2.scale);

            var tweenTime:Float = 0.1;

            var baseSquash:Float = 0.8;
            var squashP1:Float = 1 - ((1 - baseSquash) * p1Mult); // Сильнее при высоком HP
            var squashP2:Float = 1 - ((1 - baseSquash) * p2Mult);

            if (curBeat % 2 == 0)
            {
                squashP1 -= 0.1; // Еще сильнее
                squashP2 -= 0.1;
            }
            
            // Сначала устанавливаем сжатие
            iconP1.scale.set(1, squashP1);
            iconP2.scale.set(1, squashP2);
            
            // ВАЖНО: origin должен быть установлен ДО updateHitbox
            iconP1.origin.set(iconP1.frameWidth / 2, iconP1.frameHeight);
            iconP2.origin.set(iconP2.frameWidth / 2, iconP2.frameHeight);
            
            iconP1.updateHitbox();
            iconP2.updateHitbox();

            // Возврат к нормальному с восстановлением origin
            FlxTween.tween(iconP1.scale, {y: 1}, tweenTime, {
                ease: FlxEase.backOut,
                onComplete: function(twn:FlxTween) {
                    iconP1.origin.set(iconP1.frameWidth / 2, iconP1.frameHeight / 2);
                    iconP1.updateHitbox();
                }
            });
            FlxTween.tween(iconP2.scale, {y: 1}, tweenTime, {
                ease: FlxEase.backOut,
                onComplete: function(twn:FlxTween) {
                    iconP2.origin.set(iconP2.frameWidth / 2, iconP2.frameHeight / 2);
                    iconP2.updateHitbox();
                }
            });

        case 'None':
            // Ничего не делаем

        default:
            // Fallback to Psych
            iconP1.scale.set(1.2, 1.2);
            iconP2.scale.set(1.2, 1.2);
            iconP1.updateHitbox();
            iconP2.updateHitbox();
    }

    characterBopper(curBeat);
    super.beatHit();
    lastBeatHit = curBeat;
    setOnScripts('curBeat', curBeat);
    callOnScripts('onBeatHit');
}

	public function characterBopper(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void
	{
		var anim:String = boyfriend.getAnimationName();
		if(boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit()
	{
		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
			{
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (Iris.instances.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		var newScript:HScript = null;
		try
		{
			newScript = new HScript(null, file);
			if (newScript.exists('onCreate')) newScript.call('onCreate');
			trace('initialized hscript interp successfully: $file');
			hscriptArray.push(newScript);
		}
		catch(e:IrisError)
		{
			var pos:HScriptInfos = cast {fileName: file, showLine: false};
			Iris.error(Printer.errorToString(e, false), pos);
			var newScript:HScript = cast (Iris.instances.get(file), HScript);
			if(newScript != null)
				newScript.destroy();
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;

		for(script in hscriptArray)
		{
			@:privateAccess
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var callValue = script.call(funcToCall, args);
			if(callValue != null)
			{
				var myValue:Dynamic = callValue.returnValue;

				if((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
				{
					returnVal = myValue;
					break;
				}

				if(myValue != null && !excludeValues.contains(myValue))
					returnVal = myValue;
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public var ratingFCCompact:String;
	public function RecalculateRating(badHit:Bool = false, scoreBop:Bool = true) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);
		setOnScripts('opponentCombo', opponentCombo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != LuaUtils.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
	}

	public function getRatingLetter(ratingName:String):String
{
    var percent:Float = ratingPercent;
    
    if(percent >= 0.69 && percent < 0.70 && ratingName == 'pefretc') {
        return '69';
    }
    
    switch(ratingName) {
        case 'PERFECT!!!':
            return 'P';
        case 'amazing!!':
            return 'S';
        case 'so great!':
            return 'A';
        case 'good, good':
            return 'B';
        case 'pefretc':
            return '69';
        case 'mid':
            return 'C';
        case 'not bad!' | 'keep trying':
            return 'D';
        case 'damnit' | 'just close the game.':
            return 'F';
        default:
            return '?';
    }
}
	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if(cpuControlled) return;

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					#if BASE_GAME_FILES
					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
					#end
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end
	public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader
	{
		#if (!flash && sys)
		if(!ClientPrefs.data.shaders) return new ErrorHandledRuntimeShader(shaderName);

		if(!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName))
		{
			FlxG.log.warn('Shader $shaderName is missing!');
			return new ErrorHandledRuntimeShader(shaderName);
		}

		var arr:Array<String> = runtimeShaders.get(shaderName);
		return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (!flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if(FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else frag = null;

			if(FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else vert = null;

			if(found)
			{
				runtimeShaders.set(name, [frag, vert]);
				//trace('Found shader $name!');
				return true;
			}
		}
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
			#else
			FlxG.log.warn('Missing shader $name .frag AND .vert files!');
			#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
}

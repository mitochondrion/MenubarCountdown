//
//  AppDelegate.swift
//  MenubarCountdown
//
//  Copyright © 2009, 2015 Kristopher Johnson. All rights reserved.
//
//  This file is part of Menubar Countdown.
//
//  Menubar Countdown is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Menubar Countdown is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Menubar Countdown.  If not, see <http://www.gnu.org/licenses/>.
//

import Cocoa
import AudioToolbox

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Initial timer setting
    var timerSettingSeconds = 25 * 60

    /// Number of seconds remaining
    var secondsRemaining = 0

    /// Indicates whether timer is running
    var isTimerRunning = false

    /// Indicates whether the timer can be paused
    var canPause = false

    /// Indicates whether the timer can be resumed
    var canResume = false

    var stopwatch: Stopwatch!

    var statusItem: NSStatusItem!

    var statusItemView: StatusItemView!

    @IBOutlet var menu: NSMenu!

    @IBOutlet var startTimerDialogController: StartTimerDialogController!

    @IBOutlet var timerExpiredAlertController: TimerExpiredAlertController!

    override init() {
        KJUserDefaults.registerUserDefaults()
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        Log.debug(message: "application did finish launching")

        stopwatch.reset()

        let statusBar = NSStatusBar.system()
        statusItem = statusBar.statusItem(withLength: NSVariableStatusItemLength)

        statusItemView = StatusItemView()
        statusItemView.statusItem = statusItem
        statusItemView.menu = menu
        statusItemView.toolTip = NSLocalizedString(
            "Menubar Countdown",
            comment: "Status Item Tooltip"
        )
        statusItem.view = statusItemView

        updateStatusItemTitle(timeRemaining: 0)

        if UserDefaults.standard.bool(forKey: KJUserDefaults.ShowStartDialogOnLaunchKey) {
            showStartTimerDialog(sender: self)
        }
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        Log.debug(message: "application will terminate")
    }

    // MARK: Timer updating

    func waitForNextSecond() {
        let elapsed = stopwatch.elapsedTimeInterval()
        let intervalToNextSecond = ceil(elapsed) - elapsed

        Timer.scheduledTimer(
            timeInterval: intervalToNextSecond,
            target: self,
            selector: Selector(("nextSecondTimerDidFire:")),
            userInfo: nil,
            repeats: false
        )
    }

    func nextSecondTimerDidFire(timer: Timer) {
        if isTimerRunning {
            secondsRemaining = Int(round(TimeInterval(timerSettingSeconds) - stopwatch.elapsedTimeInterval()))
            DTraceTimerTick(Int32(secondsRemaining))

            if secondsRemaining <= 0 {
                timerDidExpire()
            } else {
                updateStatusItemTitle(timeRemaining: secondsRemaining)
                waitForNextSecond()
            }
        } else {
            Log.debug(message: "ignoring tick because timer is not running")
        }
    }

    func updateStatusItemTitle( timeRemaining: Int) {
        var timeRemaining = timeRemaining
        let showSeconds = UserDefaults.standard.bool(forKey: KJUserDefaults.ShowSeconds)

        if (!showSeconds) {
            // Round timeRemaining up to the next minute
            let minutes = Double(timeRemaining) / 60.0
            timeRemaining = Int(ceil(minutes)) * 60
        }

        let hours = timeRemaining / 3600
        timeRemaining %= 3600
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60

        // TODO: Use localized time-formatting function
        var timeString: String

        if showSeconds {
            timeString = NSString(format: "%02d:%02d:%02d", hours, minutes, seconds) as String
        } else {
            timeString = NSString(format: "%02d:%02d", hours, minutes) as String
        }

        statusItemView.title = timeString
    }

    // MARK: Timer expiration

    func timerDidExpire() {
        DTraceTimerExpired()

        canPause = false
        canResume = false

        updateStatusItemTitle(timeRemaining: 0)

        let defaults = UserDefaults.standard

        if defaults.bool(forKey: KJUserDefaults.BlinkOnExpirationKey) {
            statusItemView.isTitleBlinking = true
        }

        if defaults.bool(forKey: KJUserDefaults.PlayAlertSoundOnExpirationKey) {
            playAlertSound()
        }

        if defaults.bool(forKey: KJUserDefaults.AnnounceExpirationKey) {
            announceTimerExpired()
        }

        if defaults.bool(forKey: KJUserDefaults.ShowAlertWindowOnExpirationKey) {
            showTimerExpiredAlert()
        }
    }

    func playAlertSound() {
        if isTimerRunning && (secondsRemaining < 1) {
            Log.debug(message: "play alert sound")
            AudioServicesPlayAlertSound(kUserPreferredAlert);

            let defaults = UserDefaults.standard
            if defaults.bool(forKey: KJUserDefaults.RepeatAlertSoundOnExpirationKey) {
                var repeatInterval = TimeInterval(defaults.integer(forKey: KJUserDefaults.AlertSoundRepeatIntervalKey))

                if repeatInterval < 1.0 {
                    repeatInterval = 1.0
                }

                Log.debug(message: "schedule alert sound repeat \(repeatInterval)s")
                Timer.scheduledTimer(
                    timeInterval: repeatInterval,
                    target: self,
                    selector: #selector(AppDelegate.playAlertSound),
                    userInfo: nil,
                    repeats: false
                )
            }
        }
    }

    func announceTimerExpired() {
        let text = announcementText()
        Log.debug(message: "speaking announcement \"\(text)\"")

        if let synth = NSSpeechSynthesizer(voice: nil) {
            synth.startSpeaking(text)
        } else {
            Log.error(message: "unable to initialize speech synthesizer")
        }
    }

    func announcementText() -> String {
        var result = UserDefaults.standard.string(forKey: KJUserDefaults.AnnouncementTextKey)
        if (result == nil) || result!.isEmpty {
            result = NSLocalizedString(
                "The Menubar Countdown timer has reached zero.",
                comment: "Default announcement text"
            )
        }
        return result!
    }

    func showTimerExpiredAlert() {
        Log.debug(message: "show timer-expired alert")

        NSApp.activate(ignoringOtherApps: true)

        if timerExpiredAlertController == nil {
            Bundle.main.loadNibNamed(
                "TimerExpiredAlert",
                owner: self,
                topLevelObjects: nil
            )
            assert(timerExpiredAlertController != nil, "timerExpiredAlertController outlet must be set")
        }

        timerExpiredAlertController.showAlert()
    }

    // MARK: Menu item and button event handlers

    @IBAction func showStartTimerDialog(sender: AnyObject) {
        Log.debug(message: "show start timer dialog")

        dismissTimerExpiredAlert(sender: sender)

        if startTimerDialogController == nil {
            Bundle.main.loadNibNamed(
                "StartTimerDialog",
                owner: self,
                topLevelObjects: nil
            )
            assert(startTimerDialogController != nil, "startTimerDialogController must be set")
        }

        startTimerDialogController.showDialog()
    }

    @IBAction func startTimerDialogStartButtonWasClicked(sender: AnyObject) {
        Log.debug(message: "start button was clicked")

        dismissTimerExpiredAlert(sender: sender)

        startTimerDialogController.dismissDialog(sender: sender)

        UserDefaults.standard.synchronize()

        timerSettingSeconds = Int(startTimerDialogController.timerInterval)
        DTraceStartTimer(Int32(timerSettingSeconds))

        isTimerRunning = true
        canPause = true
        canResume = true
        stopwatch.reset()

        updateStatusItemTitle(timeRemaining: timerSettingSeconds)
        statusItemView.showTitle()

        waitForNextSecond()
    }

    @IBAction func stopTimer(sender: AnyObject) {
        Log.debug(message: "stop timer")
        DTraceStartTimer(Int32(secondsRemaining))

        isTimerRunning = false
        canPause = false
        canResume = false

        statusItemView.isTitleBlinking = false
        statusItemView.showIcon()
    }

    @IBAction func pauseTimer(sender: AnyObject) {
        Log.debug(message: "pause timer")
        DTracePauseTimer(Int32(secondsRemaining))

        isTimerRunning = false
        canPause = false
        canResume = true
    }

    @IBAction func resumeTimer(sender: AnyObject) {
        Log.debug(message: "resume timer")
        DTraceResumeTimer(Int32(secondsRemaining))

        isTimerRunning = true
        canPause = false
        canResume = false

        timerSettingSeconds = secondsRemaining

        stopwatch.reset()

        updateStatusItemTitle(timeRemaining: timerSettingSeconds)
        statusItemView.showTitle()

        waitForNextSecond()
    }

    @IBAction func dismissTimerExpiredAlert(sender: AnyObject) {
        Log.debug(message: "dismiss timer expired alert")

        if timerExpiredAlertController != nil {
            timerExpiredAlertController.close()
        }

        stopTimer(sender: sender)
    }

    @IBAction func restartCountdownWasClicked(sender: AnyObject) {
        Log.debug(message: "restart countdown was clicked")
        dismissTimerExpiredAlert(sender: sender)
        showStartTimerDialog(sender: sender)
    }

    @IBAction func showAboutPanel(sender: AnyObject) {
        Log.debug(message: "show About panel")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
}

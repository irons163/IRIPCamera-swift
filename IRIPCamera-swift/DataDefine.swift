//
//  DataDefine.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

// Stream settings and audio information
let GET_STREAM_SETTINGS = "GetVideoStreamSettings"
let GET_AUDIOOUT_INFO = "GetTwowayAudioInfo"

// Tags and keys
let GET_FISHEYE_CENTER_TAG = "GetFishEyeCenterResult"
let SETTING_LANGUAGE_KEY = "SettingLanguages"

let ENABLE_RTSP_URL_KEY = "EnableRTSPURL"
let RTSP_URL_KEY = "RTSPURL"

// Language keys
let LANGUAGE_ENGLISH_SHORT_ID = "en"
let LANGUAGE_CHINESE_TRADITIONAL_SHORT_ID = "zh-Hant"
let LANGUAGE_CHINESE_SIMPLIFIED_SHORT_ID = "zh-Hans"

// Maximum retry attempts
let MAX_RETRY_TIMES = 3

// Port definitions
let HTTPS_APP_COMMAND_PORT = 9091
let HTTP_APP_COMMAND_PORT = 9090
let VIDEO_PORT = 554
let AUDIO_PORT = 2000
let NORMAL_PORT = 8080
let DOWNLOAD_PORT = 9000

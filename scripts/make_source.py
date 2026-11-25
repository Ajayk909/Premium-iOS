"""Writes sidestore-source.json: the feed SideStore/AltStore read to find new Premium builds."""
import json, os, sys, datetime

version, build, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
repo = "Ajayk909/Premium-iOS"
raw = f"https://raw.githubusercontent.com/{repo}/main"
path = "sidestore-source.json"

try:
    source = json.load(open(path))
    old = source["apps"][0]["versions"]
except Exception:
    old = []

entry = {
    "version": version,
    "buildVersion": build,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": f"Build {build}",
    "downloadURL": f"https://github.com/{repo}/releases/download/build-{build}/Premium-unsigned.ipa",
    "size": size,
    "minOSVersion": "17.0",
}
versions = [entry] + [v for v in old if v.get("buildVersion") != build][:9]

source = {
    "name": "Premium",
    "identifier": "com.ajayk909.premium.source",
    "subtitle": "AJ's ad-free YouTube app",
    "sourceURL": f"{raw}/{path}",
    "iconURL": f"{raw}/Premium/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
    "tintColor": "#1C1D24",
    "apps": [{
        "name": "Premium",
        "bundleIdentifier": "com.ajayk909.premium",
        "developerName": "AJ",
        "subtitle": "Ad-free YouTube with Pearl Glass",
        "localizedDescription": "Personal, open-source, ad-free YouTube client.",
        "iconURL": f"{raw}/Premium/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "tintColor": "#1C1D24",
        "category": "entertainment",
        "versions": versions,
        "appPermissions": {"entitlements": [], "privacy": {
            "NSMicrophoneUsageDescription": "Voice search",
            "NSSpeechRecognitionUsageDescription": "Voice search",
            "NSLocalNetworkUsageDescription": "Find your Roku TV"}},
    }],
    "news": [],
}
json.dump(source, open(path, "w"), indent=2)
print(f"source updated to {version} ({build})")

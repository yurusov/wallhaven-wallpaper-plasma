 /*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2022 Link Dupont <link@sub-pop.net>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.5
import QtQuick.Controls 2.1 as QQC2
import QtQuick.Window 2.2
import org.kde.plasma.wallpapers.image 2.0 as Wallpaper
import org.kde.plasma.core 2.0 as PlasmaCore

QQC2.StackView {
    id: root

    property url currentUrl
    property int currentPage
    property int currentIndex

    readonly property int fillMode: wallpaper.configuration.FillMode
    readonly property string configColor: wallpaper.configuration.Color
    readonly property bool blur: wallpaper.configuration.Blur
    readonly property bool refreshSignal: wallpaper.configuration.RefetchSignal
    readonly property string sorting: wallpaper.configuration.Sorting

    readonly property size sourceSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)

    function greatestCommonDenominator(a, b) {
        return (b == 0) ? a : greatestCommonDenominator(b, a%b);
    }
    readonly property string aspectRatio: {
        var d = greatestCommonDenominator(root.width, root.height)
        return root.width / d + "x" + root.height / d;
    }

    property Item pendingImage

    onCurrentUrlChanged: Qt.callLater(loadImage);
    onFillModeChanged: Qt.callLater(loadImage);
    onConfigColorChanged: Qt.callLater(loadImage);
    onBlurChanged: Qt.callLater(loadImage);
    onRefreshSignalChanged: refreshTimer.restart();
    onSortingChanged: {
        if (sorting != "random") {
            currentPage = 1;
            currentIndex = 0;
        }
    }

    Component.onCompleted: refreshImage();

    Timer {
        id: refreshTimer
        interval: wallpaper.configuration.WallpaperDelay * 60 * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            console.log("refreshTimer triggered");
            refreshImage();
        }
    }

    property Component mainImage: Component {
        Image {
            id: mainImage

            Rectangle {
                id: backgroundColor
                color: "black"
                anchors.fill: parent
                visible: mainImage.status === Image.Ready
                z: -2
            }
        }
    }

    Timer {
        id: delayTimer
        function setTimeout(callback, delayTime) {
            delayTimer.interval = delayTime;
            delayTimer.repeat = false;
            delayTimer.triggered.connect(callback);
            delayTimer.triggered.connect(function release () {
                delayTimer.triggered.disconnect(callback);
                delayTimer.triggered.disconnect(release);
            });
            delayTimer.start();
        }
    }


    function refreshImage() {
        getImageData().then(pickImage).catch(e => {
            console.error(e);
            wallpaper.configuration.ErrorText = e;
            root.currentUrl = "blackscreen.jpg";
            loadImage();
        });
    }

    function getImageData() {
        return new Promise((res, rej) => {
            var url = `https://wallhaven.cc/api/v1/search?`

            var categories = ""
            if (wallpaper.configuration.CategoryGeneral) {
                categories += "1";
            } else {
                categories += "0";
            }
            if (wallpaper.configuration.CategoryAnime) {
                categories += "1";
            } else {
                categories += "0";
            }
            if (wallpaper.configuration.CategoryPeople) {
                categories += "1";
            } else {
                categories += "0";
            }
            url += `categories=${categories}&`

            var purity = "";
            if (wallpaper.configuration.PuritySFW) {
                purity += "1";
            } else {
                purity += "0";
            }
            if (wallpaper.configuration.PuritySketchy) {
                purity += "1";
            } else {
                purity += "0";
            }
            if (wallpaper.configuration.PurityNSFW) {
                purity += "1";
            } else {
                purity += "0";
            }
            url += `purity=${purity}&`

            url += `sorting=${wallpaper.configuration.Sorting}&`

            if (wallpaper.configuration.Sorting != "random") {
                url += `page=${root.currentPage}&`
            }

            url += `atleast=${root.sourceSize.width}x${root.sourceSize.height}&`

            if (wallpaper.configuration.Sorting == "toplist") {
                url += `topRange=${wallpaper.configuration.TopRange}&`
            }

            // if (wallpaper.configuration.SearchColor) {
            //     url += `color=${wallpaper.configuration.SearchColor}&`
            // }

            if (!wallpaper.configuration.RatioAny) {
                var ratios = []
                if (wallpaper.configuration.Ratio169) {
                    ratios.push("16x9");
                }
                if (wallpaper.configuration.Ratio1610) {
                    ratios.push("16x10");
                }
                if (wallpaper.configuration.RatioCustom) {
                    ratios.push(wallpaper.configuration.RatioCustomValue);
                }
                url += `ratios=${ratios.join(',')}&`
            }

            url += `q=${encodeURIComponent(wallpaper.configuration.Query)}`
            console.error('using url: ' + url);

            var errorCount = 0;
            const xhr = new XMLHttpRequest();
            xhr.onload = () => {
                if (xhr.status != 200) {
                    return rej("request error: " + xhr.responseText);
                }

                let data = {};
                try {
                    data = JSON.parse(xhr.responseText);
                } catch (e) {
                    return rej("cannot parse response as JSON: " + xhr.responseText);
                }
                res(data);
            };
            xhr.onerror = () => {
                if (errorCount >= 3) {
                    rej("failed to send request");
                } else {
                    ++errorCount;
                    console.error('request error, queueing retry ' + errorCount + '/3');
                    delayTimer.setTimeout(function () { sendRequest(xhr, url); }, 5000);
                }
            };
            sendRequest(xhr, url);
        });
    }

    function sendRequest(request, url) {
            request.open('GET', url);
            request.setRequestHeader('X-API-Key', wallpaper.configuration.APIKey);
            request.setRequestHeader('User-Agent','wallhaven-wallpaper-kde-plugin');
            request.timeout = 15000;
            request.send();
    }

    function pickImage(d) {
        if (d.data.length > 0) {
            var index = 0;
            if (wallpaper.configuration.Sorting != "random") {
                index = root.currentIndex;
                if (index > 24) {
                    root.currentPage += 1;
                    root.currentIndex = 0;
                    refreshTimer.restart();
                    return;
                }
                root.currentIndex += 1;
            } else {
                index = Math.floor(Math.random() * d.data.length);
            }
            const imageObj = d.data[index] || {};
            root.currentUrl = imageObj.path;
            root.currentPage = d.meta.current_page;
            wallpaper.configuration.currentWallpaperThumbnail = imageObj.thumbs.small
            wallpaper.configuration.currentWallpaperUrl = imageObj.url
            wallpaper.configuration.ErrorText = "";
        } else {
            wallpaper.configuration.ErrorText = "No wallpapers found";
            wallpaper.configuration.currentWallpaperThumbnail = "";
            wallpaper.configuration.currentWallpaperUrl = "";
            root.currentUrl = "blackscreen.jpg";
        }
        loadImage();
    }

    function loadImage() {
        if (pendingImage) {
            pendingImage.statusChanged.disconnect(replaceWhenLoaded);
            pendingImage.destroy();
            pendingImage = null;
        }

        pendingImage = root.mainImage.createObject(root, {
            "source": root.currentUrl,
            "fillMode": root.fillMode,
            "sourceSize": root.sourceSize,
            "color": root.configColor,
            "blur": root.blur,
            "opacity": 0,
            "width": root.width,
            "height": root.height,
        });

        pendingImage.statusChanged.connect(replaceWhenLoaded);
        replaceWhenLoaded();
    }

    function replaceWhenLoaded() {
        if (pendingImage.status === Image.Loading) {
            return;
        }

        pendingImage.statusChanged.disconnect(replaceWhenLoaded);
        pendingImage.QQC2.StackView.onActivated.connect(wallpaper.repaintNeeded);
        pendingImage.QQC2.StackView.onRemoved.connect(pendingImage.destroy);
        root.replace(pendingImage, {}, QQC2.StackView.Transition);

        wallpaper.loading = false;

        pendingImage = null;
    }

    replaceEnter: Transition {
        OpacityAnimator {
            id: replaceEnterOpacityAnimator
            from: 0
            to: 1
            // The value is to keep compatible with the old feeling defined by "TransitionAnimationDuration" (default: 1000)
            // 1 is HACK for https://bugreports.qt.io/browse/QTBUG-106797 to avoid flickering
            duration: root.doesSkipAnimation ? 1 : Math.round(PlasmaCore.Units.veryLongDuration * 2.5)
        }
    }
    // Keep the old image around till the new one is fully faded in
    // If we fade both at the same time you can see the background behind glimpse through
    replaceExit: Transition{
        PauseAnimation {
            duration: replaceEnterOpacityAnimator.duration
        }
    }

}

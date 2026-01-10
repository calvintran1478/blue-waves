import { useContext, Signal, createEffect, Show, createSignal } from "solid-js";
import { Store } from "solid-js/store";
import { apiDomain, AuthContext, MusicPlayerStateContext } from "../index.tsx"; 
import { getToken } from "../utils/token";
import { openDB } from "idb";
import soundPng from "../assets/sound.png";
import mutePng from "../assets/mute.png";
import playSvg from "../assets/play.svg";
import pauseSvg from "../assets/pause.svg";
import prevSvg from "../assets/prev.svg";
import nextSvg from "../assets/next.svg";

const MusicPlayer = () => {
    const [musicFile, setMusicFile] = createSignal("");
    const [coverArtFile, setCoverArtFile] = createSignal("");

    const [playing, setPlaying] = createSignal(true);
    const [seeking, setSeeking] = createSignal(false);

    const [currentTime, setCurrentTime] = createSignal("00:00");
    const [endTime, setEndTime] = createSignal("00:00");

    const [mute, setMute] = createSignal(false);
    
    const [token, setToken] = useContext(AuthContext) as Signal<string>;
    const [store, setStore] = useContext(MusicPlayerStateContext) as Store<any>;

    const musicId = () => store.musicList[store.musicIndex]["music_id"] // Derived signal
    const musicTitle = () => store.musicList[store.musicIndex]["title"] // Derived signal
    const musicArtist = () => store.musicList[store.musicIndex]["artist"] // Derived signal

    let previousVolume = "0";
    let audioPlayer!: HTMLAudioElement;
    let seekControl!: HTMLInputElement;
    let volumeControl!: HTMLInputElement;

    const getTimeString = (time: number) => {
        let seconds = Math.floor(time);
        let minutes = 0;
        while (seconds >= 60) {
            minutes += 1;
            seconds -= 60;
        }

        const minuteString = minutes < 10 ? `0${minutes}` : minutes.toString();
        const secondsString = seconds < 10 ? `0${seconds}` : seconds.toString();
        return `${minuteString}:${secondsString}`;
    }

    const fetchMusicFile = async (mid : string) => {
        // Open music database
        const db = await openDB("musicFileDB", 1, {
            upgrade(database) {
                database.createObjectStore("musicFiles", { keyPath: "music_id" });
                database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
            },
        })

        // Check music database for a cached value
        const musicFileEntry = await db.get("musicFiles", mid);
        if (musicFileEntry !== undefined) {
            // If cached value exists use it
            const blob = new Blob([musicFileEntry["music_buffer"]]);
            const url = window.URL.createObjectURL(blob);
            return url;
        } else {
            // Fetch new token if user refreshed the page
            if (token() === "") setToken(await getToken());

            // If no cached value exists perform a normal request for the music file
            const response = await fetch(`${apiDomain}/api/v1/users/music/${mid}`, {
                headers: { "Authorization": `Bearer ${token()}` },
                credentials: "omit",
                referrerPolicy: "no-referrer"
            });

            if (response.ok) {
                // Decode data as a music file
                const musicBuffer = await response.arrayBuffer();
                const blob = new Blob([musicBuffer]);
                const url = window.URL.createObjectURL(blob);

                // Cache music file for later requests
                await db.put("musicFiles", {music_id: mid, music_buffer: musicBuffer});

                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchMusicFile(mid);
            }
        }
    }
    
    const fetchCoverArtFile = async (mid : string) => {
        // Open music database
        const db = await openDB("musicFileDB", 1, {
            upgrade(database) {
                database.createObjectStore("musicFiles", { keyPath: "music_id" });
                database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
            },
        })

        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Check music database for a cached value
        const coverArtFileEntry = await db.get("coverArtFiles", mid);
        if (coverArtFileEntry !== undefined) {
            // If a cached value exists perform a conditional request
            const response = await fetch(`${apiDomain}/api/v1/users/music/${mid}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${token()}`,
                    "If-Modified-Since": coverArtFileEntry["last_modified"]
                },
                credentials: "omit",
                referrerPolicy: "no-referrer"
            });

            if (response.ok) {
                // Cache miss: decode new data and update cache
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                await db.put("coverArtFiles", {music_id: mid, image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                return url;
            } else if (response.status === 304) {
                const blob = new Blob([coverArtFileEntry["image_buffer"]]);
                const url = window.URL.createObjectURL(blob);
                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchCoverArtFile(mid);
            }
        } else {
            // If no cached value exists perform a normal request for the music file
            const response = await fetch(`${apiDomain}/api/v1/users/music/${mid}/cover-art`, {
                headers: { "Authorization": `Bearer ${token()}` },
                credentials: "omit",
                referrerPolicy: "no-referrer"
            });

            if (response.ok) {
                // Decode data as an image
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                // Cache cover art file for later requests
                await db.put("coverArtFiles", {music_id: mid, image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchCoverArtFile(mid);
            }
        }
    }

    // Fetch music and cover art file whenever musid id updates and update document title
    createEffect(() => {
        if (musicId() !== "") {
            fetchMusicFile(musicId()).then((mf) => setMusicFile(mf as string));
            fetchCoverArtFile(musicId()).then((af) => setCoverArtFile(af as string));
            setPlaying(true);
            document.title = `${musicTitle()} - Blue waves`;
        }
    })

    const playPause = () => {
        setPlaying(!playing());
        if (playing()) {
            audioPlayer.play();
        } else {
            audioPlayer.pause();
        }
    }

    const playPrev = async () => {
        setStore("musicIndex", store.musicIndex === 0 ? store.musicList.length - 1 : store.musicIndex - 1);
    }

    const playNext = async () => {
        setStore("musicIndex", store.musicIndex === store.musicList.length - 1 ? 0 : store.musicIndex + 1);
    }

    const handleMute = () => {
        setMute(!mute());
        if (mute()) {
            previousVolume = volumeControl.value;
            volumeControl.value = "0";
            audioPlayer.volume = 0;
        } else {
            volumeControl.value = previousVolume;
            audioPlayer.volume = parseFloat(previousVolume);
        }
    }

    const handleTimeUpdate = () => {
        if (!seeking()) {
            seekControl.value = audioPlayer.currentTime.toString();
        }
        setCurrentTime(getTimeString(audioPlayer.currentTime));
        if (!isNaN(audioPlayer.duration)) {
            setEndTime(getTimeString(audioPlayer.duration));
        }
    }

    const handleVolumeUpdate = (event: Event) => {
        const volumeInput = event.target as HTMLInputElement;
        const newVolume = volumeInput.value;
        localStorage.setItem("volume", newVolume);

        audioPlayer.volume = parseFloat(newVolume);
        previousVolume = newVolume;
        setMute(false);
    }

    return (
        <Show when={store.showMusicPlayer}>
            <div class="flex fixed bottom-0 w-screen h-20 border justify-between items-center bg-gray-100">
            <audio ref={audioPlayer} autoplay={true} onTimeUpdate={handleTimeUpdate} onEnded={playNext} src={musicFile()}></audio>
                <div class="flex items-center ml-4">
                    <img class="w-16 h-16 rounded object-cover" src={coverArtFile()}/>
                    <div class="mx-4">
                        <p class="font-semibold">{musicTitle()}</p>
                        <p>{musicArtist()}</p>
                    </div>
                    <p>{currentTime()}</p>
                    <input class="mx-2 w-40" ref={seekControl} onInput={() => setSeeking(true)} onMouseUp={() => setSeeking(false)} onChange={(event) => {audioPlayer.currentTime = parseInt(event.target.value)}} type="range" id="seek" name="seek" value={0} min="0" max={audioPlayer.duration}/>
                    <p>{endTime()}</p>
                </div>
                <div>
                    <button onClick={playPrev}>
                        <img class="size-6" src={prevSvg} alt="prev"/>
                    </button>
                    <button class="mx-12" onClick={playPause}>
                        <img class="size-6" src={playing() ? pauseSvg : playSvg} alt={playing() ? "pause" : "play"}/>
                    </button>
                    <button onClick={playNext}>
                        <img class="size-6" src={nextSvg} alt="next"/>
                    </button>
                </div>
                <div class="flex">
                    <button onClick={handleMute}>
                        <img class="w-8 h-8 mx-4" src={mute() ? mutePng : soundPng}/>
                    </button>
                    <input class="w-40" ref={volumeControl} onInput={handleVolumeUpdate} type="range" id="sound" name="sound" step="0.02" value={localStorage.getItem("volume") ?? "1"} min="0" max="1"/>
                </div>
                <button class="mr-4" onClick={() => {setStore("showMusicPlayer", false); document.title = "Blue waves"}}>close</button>
            </div>
        </Show>
    )
}

export default MusicPlayer;

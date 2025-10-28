import { createSignal, useContext, Signal, Accessor, Setter, createEffect } from "solid-js";
import { AuthContext } from "../index.tsx"; 
import { getToken } from "../utils/token";
import { openDB } from "idb";

interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const MusicPlayer = (props: { closeCallback: () => void, musicList: MusicEntry[], musicIndex: Accessor<number>, setMusicIndex: Setter<number> }) => {

    const [musicFile, setMusicFile] = createSignal("");

    const [playing, setPlaying] = createSignal(true);

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const musicId = () => props.musicList[props.musicIndex()!]["music_id"] // Derived signal
    const musicTitle = () => props.musicList[props.musicIndex()!]["title"] // Derived signal

    let audioPlayer!: HTMLAudioElement;

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
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${mid}`, {
                headers: { "Authorization": `Bearer ${token()}` }
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

    // Fetch music file whenever musid id updates
    createEffect(() => {
        fetchMusicFile(musicId()).then((mf) => setMusicFile(mf as string))
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
        props.setMusicIndex(props.musicIndex() === 0 ? props.musicList.length - 1 : props.musicIndex()! - 1)
    }

    const playNext = async () => {
        props.setMusicIndex(props.musicIndex() === props.musicList.length - 1 ? 0 : props.musicIndex()! + 1)
    }

    return (
        <div class="flex fixed bottom-0 w-screen h-16 border justify-between items-center bg-gray-100">
            <p class="ml-4">{musicTitle()}</p>
            <button onClick={playPrev}>prev</button>
            <audio ref={audioPlayer} autoplay={true} onEnded={playNext} src={musicFile()}></audio>
            <button onClick={playPause}>{playing() ? "pause" : "play"}</button>
            <button onClick={playNext}>next</button>
            <button class="mr-4" onClick={props.closeCallback}>close</button>
        </div>
    )
}

export default MusicPlayer;

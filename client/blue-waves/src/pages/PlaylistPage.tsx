import { createResource, useContext, createSignal, For, Signal, Show, Suspense } from "solid-js";
import { A } from "@solidjs/router";
import { useParams } from "@solidjs/router";
import { getToken } from "../utils/token"; 
import { AuthContext } from "..";
import MusicPlayer from "../components/MusicPlayer";

const PlaylistPage = () => {
    const params = useParams();
    const playlistId = params.playlist_id;

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [playlistName, setPlaylistName] = createSignal("");
    const [showMusicPlayer, setShowMusicPlayer] = createSignal(false);

    const fetchPlaylist = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get playlist music
        const response = await fetch(`http://localhost:8080/api/v1/users/playlists/${playlistId}`, {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            const body = await response.json();
            setPlaylistName(body["name"]);
            return body["music"];
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchPlaylist();
        }
    }

    const [playlistMusic] = createResource(fetchPlaylist);

    const [musicIndex, setMusicIndex] = createSignal(0);

    return (
        <div class="flex">
            <div class="flex flex-col w-1/5 h-screen border-2">
                <nav class="flex flex-col items-center p-6">
                    <A href="/home" class="text-2xl font-medium m-6">Home</A>
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5">
                <Suspense>
                    <h1 class="text-3xl font-semibold mt-16 mb-4">{playlistName()}</h1>
                    <hr class="border my-2"/>
                    <For each={playlistMusic()}>
                        {(musicEntry, index) => (
                            <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                <button onClick={() => {setMusicIndex(index); setShowMusicPlayer(true)}}>
                                    <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                    <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                </button>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showMusicPlayer()}>
                <MusicPlayer closeCallback={() => setShowMusicPlayer(false)} musicList={playlistMusic()} musicIndex={musicIndex} setMusicIndex={setMusicIndex}/>
            </Show>
        </div>
    )
}

export default PlaylistPage;

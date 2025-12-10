import { createResource, useContext, createSignal, For, Signal, Show, Suspense } from "solid-js";
import { A } from "@solidjs/router";
import { useParams } from "@solidjs/router";
import { getToken } from "../utils/token"; 
import { apiDomain, AuthContext } from "../index.tsx";
import AddPlaylistMusicModal from "../components/AddPlaylistMusicModal"; 
import MusicPlayer from "../components/MusicPlayer";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const PlaylistPage = () => {
    document.title = "Blue waves";
    
    const params = useParams();
    const playlistId = params.playlist_id;

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [playlistName, setPlaylistName] = createSignal("");
    const [showAddPlaylistMusicModal, setShowAddPlaylistMusicModal] = createSignal(false);
    const [showMusicPlayer, setShowMusicPlayer] = createSignal(false);

    const [editMode, setEditMode] = createSignal(false);

    const fetchPlaylist = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get playlist music
        const response = await fetch(`${apiDomain}/api/v1/users/playlists/${playlistId}`, {
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

    const updateIndexUp = async (musicId: string) => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Check if new state is valid
        const inputElement = (document.querySelector(`#${musicId}`) as HTMLInputElement);
        const newPosition = parseInt(inputElement.value) - 1;
        if (newPosition === 0) {
            return;
        }

        // Encode position as bytes
        const buffer = new ArrayBuffer(4);
        const view = new DataView(buffer);
        view.setInt32(0, newPosition, false);

        const response = await fetch(`${apiDomain}/api/v1/users/playlists/${playlistId}/music/${musicId}`, {
            method: "PATCH",
            headers: { "Authorization": `Bearer ${token()}` },
            body: buffer
        });

        if (response.ok) {
            // Decrement index
            inputElement.stepDown();

            // Swap indices
            const oldIndex = playlistMusic().findIndex((musicEntry: MusicEntry) => musicEntry["music_id"] === musicId);
            const newIndex = newPosition - 1;

            const newPlaylistMusic = [...playlistMusic()];
            const temp = newPlaylistMusic[oldIndex];
            newPlaylistMusic[oldIndex] = newPlaylistMusic[newIndex];
            newPlaylistMusic[newIndex] = temp;

            modifyPlaylistMusic.mutate(newPlaylistMusic);
        } else if (response.status === 401) {
            setToken(await getToken());
            await updateIndexUp(musicId);
        }
    }

    const updateIndexDown = async (musicId: string) => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Check if new state is valid
        const inputElement = (document.querySelector(`#${musicId}`) as HTMLInputElement);
        const newPosition = parseInt(inputElement.value) + 1;
        if (newPosition === playlistMusic().length + 1) {
            return;
        }

        // Encode position as bytes
        const buffer = new ArrayBuffer(4);
        const view = new DataView(buffer);
        view.setInt32(0, newPosition, false);

        const response = await fetch(`${apiDomain}/api/v1/users/playlists/${playlistId}/music/${musicId}`, {
            method: "PATCH",
            headers: { "Authorization": `Bearer ${token()}` },
            body: buffer
        });

        if (response.ok) {
            // Increment index
            inputElement.stepUp();

            // Swap indices
            const oldIndex = playlistMusic().findIndex((musicEntry: MusicEntry) => musicEntry["music_id"] === musicId);
            const newIndex = newPosition - 1;

            const newPlaylistMusic = [...playlistMusic()];
            const temp = newPlaylistMusic[oldIndex];
            newPlaylistMusic[oldIndex] = newPlaylistMusic[newIndex];
            newPlaylistMusic[newIndex] = temp;

            modifyPlaylistMusic.mutate(newPlaylistMusic);
        } else if (response.status === 401) {
            setToken(await getToken());
            await updateIndexUp(musicId);
        }
    }

    const deleteMusic = async (event: Event, musicId: string) => {
        event.preventDefault();

        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Remove music from playlist
        const response = await fetch(`${apiDomain}/api/v1/users/playlists/${playlistId}/music/${musicId}`, {
            method: "DELETE",
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            // Delete playlist entry
            const newPlaylistMusic = [...playlistMusic()];
            const playlistIndex = playlistMusic().findIndex((musicEntry: MusicEntry) => musicEntry["music_id"] === musicId);
            newPlaylistMusic.splice(playlistIndex, 1);
            modifyPlaylistMusic.mutate(newPlaylistMusic);
        } else if (response.status === 401) {
            setToken(await getToken());
            await deleteMusic(event, musicId);
        }
    }

    const [playlistMusic, modifyPlaylistMusic] = createResource(fetchPlaylist);

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
                    <div>
                        <button class="rounded w-24 h-10 border-2 my-2" onClick={() => setShowAddPlaylistMusicModal(true)}>Add Music</button>
                        <button class={`rounded w-24 h-10 border-2 mx-4 my-2 ${editMode() ? "bg-gray-100" : ""}`} onClick={() => setEditMode(!editMode())}>{editMode() ? "Done" : "Edit Music"}</button>
                    </div>
                    <hr class="border my-2"/>
                    <For each={playlistMusic()}>
                        {(musicEntry, index) => (
                            <div>
                                <Show when={!editMode()}>
                                    <button class="flex flex-col justify-center items-start h-16 w-full my-2 border-2" onClick={() => {setMusicIndex(index); setShowMusicPlayer(true)}}>
                                        <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                        <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                    </button>
                                </Show>
                                <Show when={editMode()}>
                                    <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                        <div>
                                            <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                            <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                        </div>
                                        <div class="flex">
                                            <button class="p-1 rounded border" onClick={(event) => deleteMusic(event, musicEntry["music_id"])}>Delete</button>
                                            <input disabled id={musicEntry["music_id"]} class="p-1 w-8 ml-8 mr-2 rounded border [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none" type="number" min={1} max={playlistMusic().length} value={index()+1}/>
                                            <div class="flex flex-col mr-4">
                                                <button class="flex justify-center items-center rounded-t border w-5 p-1 h-4 bg-gray-100 hover:bg-gray-200" onClick={() => updateIndexUp(musicEntry["music_id"])}>^</button>
                                                <button class="flex justify-center items-center rounded-b border w-5 p-1 h-4 bg-gray-100 hover:bg-gray-200" onClick={() => updateIndexDown(musicEntry["music_id"])}>v</button>
                                            </div>
                                        </div>
                                    </div>
                                </Show>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showMusicPlayer()}>
                <MusicPlayer closeCallback={() => {setShowMusicPlayer(false); document.title = "Blue waves"}} musicList={playlistMusic()} musicIndex={musicIndex} setMusicIndex={setMusicIndex}/>
            </Show>
            <Show when={showAddPlaylistMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <AddPlaylistMusicModal closeCallback={() => setShowAddPlaylistMusicModal(false)} playlistId={playlistId} playlistMusic={playlistMusic} setPlaylistMusic={modifyPlaylistMusic.mutate}/>
                </div>
            </Show>
        </div>
    )
}

export default PlaylistPage;

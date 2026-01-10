import { createSignal, createResource, useContext, Switch, Match, Accessor, Resource, Signal, Setter, Show } from "solid-js";
import { until } from "@solid-primitives/promise"; 
import { openDB } from "idb";
import { getToken } from "../utils/token";
import { apiDomain, AuthContext } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const UpdateMusicModal = (props: { musicId: Accessor<string>, setMusicId: Setter<string>, closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>, coverArtUrl: Accessor<string>, fetchCoverArtLoading: Accessor<boolean>}) => {
    const musicEntryIndex = props.musicEntries()!.findIndex((musicEntry) => musicEntry["music_id"] === props.musicId());
    const musicEntry = props.musicEntries()![musicEntryIndex];

    const [setCoverArtLoading, setSetCoverArtLoading] = createSignal(false);
    const [deleteMusicLoading, setDeleteMusicLoading] = createSignal(false);

    let title = musicEntry["title"];
    let artist = musicEntry["artist"];
    let artInput!: HTMLInputElement;

    const originalTitle = title;
    const originalArtist = artist;

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [coverArtFile] = createResource(async () => {
        await until(() => !props.fetchCoverArtLoading());
        return props.coverArtUrl();
    });

    const updateMusic = async() => {
        // Update music metadata
        const response = await fetch(`${apiDomain}/api/v1/users/music/${props.musicId()}`, {
            method: "PATCH",
            headers: {
                "Content-Type": "text/plain",
                "Authorization": `Bearer ${token()}`
            },
            credentials: "omit",
            body: `${title !== originalTitle ? `1${title}` : "0"}\n${artist !== originalArtist ? `1${artist}` : "0"}`
        });

        if (response.ok) {
            // Update music entry
            const newMusicEntries = [...props.musicEntries()!];
            newMusicEntries[musicEntryIndex] = {"music_id": props.musicId(), "title": title, "artist": artist};
            props.setMusicEntries(newMusicEntries);
        } else if (response.status === 401) {
            setToken(await getToken());
            await updateMusic();
        }
    }

    const deleteMusic = async(event: Event) => {
        event.preventDefault();
        setDeleteMusicLoading(true);

        const response = await fetch(`${apiDomain}/api/v1/users/music/${props.musicId()}`, {
            method: "DELETE",
            headers: { "Authorization": `Bearer ${token()}` },
            credentials: "omit"
        });

        if (response.ok) {
            // Delete music entry
            const newMusicEntries = [...props.musicEntries()!];
            newMusicEntries.splice(musicEntryIndex, 1);
            props.setMusicEntries(newMusicEntries);

            // Delete cache entry
            const db = await openDB("musicFileDB", 1, {
                upgrade(database) {
                    database.createObjectStore("musicFiles", { keyPath: "music_id" });
                    database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
                },
            })
            await db.delete("musicFiles", props.musicId());
            await db.delete("coverArtFiles", props.musicId());

            // Close modal
            props.closeCallback();
        } else if (response.status === 401) {
            setToken(await getToken());
            await deleteMusic(event);
        }

        setDeleteMusicLoading(false);
    }

    const setCoverArt = async () => {
        // Set cover art
        setSetCoverArtLoading(true);
        const response = await fetch(`${apiDomain}/api/v1/users/music/${props.musicId()}/cover-art`, {
            method: "PUT",
            headers: { "Authorization": `Bearer ${token()}` },
            credentials: "omit",
            body: artInput.files![0]
        })

        if (response.ok) {
            // Invalidate cover art cache
            const db = await openDB("musicFileDB", 1, {
                upgrade(database) {
                    database.createObjectStore("musicFiles", { keyPath: "music_id" });
                    database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
                },
            })
            await db.delete("coverArtFiles", props.musicId());
            props.setMusicId("");
        } else if (response.status === 401) {
            setToken(await getToken());
            await setCoverArt();
        }
        setSetCoverArtLoading(false);
    }

    const handleUpdate = async (event: Event) => {
        event.preventDefault();
        // Change title and artist
        const updatePromises = [];
        if (title !== originalTitle || artist !== originalArtist) {
            updatePromises.push(updateMusic());
        }

        // Change cover art if new one was provided
        if (artInput.files!.length === 1) {
            updatePromises.push(setCoverArt());
        }

        // Close modal
        if (updatePromises.length !== 0) await Promise.all(updatePromises);
        props.closeCallback();
    }

    return (
        <div class="p-6 bg-white" style="width: 60rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback} class="mx-5">close</button>
                <button onClick={deleteMusic}>delete</button>
            </div>
            <div class="flex justify-around">
                <form onSubmit={handleUpdate} class="flex flex-col items-center">
                    <div class="flex items-center m-4">
                        <label for="title" class="text-lg m-2">Title</label>
                        <input id="title" class="border-2 m-2 w-60 h-8" value={title} onChange={(event) => {title = event.target.value}} maxlength={150}/>
                    </div>
                    <div class="flex items-center m-4">
                        <label for="artist" class="text-lg m-2">Artist</label>
                        <input id="artist" class="border-2 m-2 w-60 h-8" value={artist} onChange={(event) => {artist = event.target.value}} maxlength={100}/>
                    </div>
                    <div class="flex items-center m-3 mr-10">
                        <label for="artFile" class="text-lg m-2">Cover Art</label>
                        <input ref={artInput} type="file" id="artFile" class="w-60 m-2"/>
                    </div>
                    <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400 mt-4" disabled={setCoverArtLoading()}>
                        <Switch fallback={<span class="mr-2">Update music</span>}>
                            <Match when={setCoverArtLoading()}>
                                <span class="mr-2">Updating</span>
                            </Match>
                            <Match when={deleteMusicLoading()}>
                                <span class="mr-2">Deleting</span>
                            </Match>
                        </Switch>
                        <Show when={setCoverArtLoading() || deleteMusicLoading()}>
                            <LoadingSpinner/>
                        </Show>
                    </button>
                </form>
                <img src={coverArtFile()} class="w-80 h-72"/>
            </div>
        </div>
    )
}

export default UpdateMusicModal;

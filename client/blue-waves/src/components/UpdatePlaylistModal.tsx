import { useContext, Resource, Signal, Setter } from "solid-js";
import { getToken } from "../utils/token"; 
import { apiDomain, AuthContext } from "../index.tsx";

// Expected fields for each playlist
interface Playlist {
    playlist_id: string,
    name: string
}

const UpdatePlaylistModal = (props: { playlistId: string, closeCallback: () => void, playlists: Resource<Playlist[]>, setPlaylists: Setter<Playlist[] | undefined> }) => {
    const playlistIndex = props.playlists()!.findIndex((playlist) => playlist["playlist_id"] === props.playlistId);
    const playlist = props.playlists()![playlistIndex];

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    let name = playlist["name"];

    const originalName = name;

    const updatePlaylist = async(event: Event) => {
        event.preventDefault();
        if (name !== originalName) {
            // Update playlist name
            const response = await fetch(`${apiDomain}/api/v1/users/playlists/${props.playlistId}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "text/plain",
                    "Authorization": `Bearer ${token()}`
                },
                credentials: "omit",
                referrerPolicy: "no-referrer",
                body: name
            });

            if (response.ok) {
                // Update playlist entry
                const newPlaylists = [...props.playlists()!];
                newPlaylists[playlistIndex] = {"playlist_id": props.playlistId, "name": name};
                props.setPlaylists(newPlaylists);
            } else if (response.status === 401) {
                setToken(await getToken());
                await updatePlaylist(event);
            }
        }
        props.closeCallback();
    }

    const deletePlaylist = async(event: Event) => {
        event.preventDefault();
        const response = await fetch(`${apiDomain}/api/v1/users/playlists/${props.playlistId}`, {
            method: "DELETE",
            headers: { "Authorization": `Bearer ${token()}` },
            credentials: "omit",
            referrerPolicy: "no-referrer"
        });

        if (response.ok) {
            // Delete playlist entry
            const newPlaylists = [...props.playlists()!];
            newPlaylists.splice(playlistIndex, 1);
            props.setPlaylists(newPlaylists);

            // Close modal
            props.closeCallback();
        } else if (response.status === 401) {
            setToken(await getToken());
            await deletePlaylist(event);
        }
    }

    return (
        <div class="p-6 bg-white" style="width: 36rem; height: 16rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback} class="mx-5">close</button>
                <button onClick={deletePlaylist}>delete</button>
            </div>
            <form onSubmit={updatePlaylist} class="flex flex-col justify-center items-center">
                <div class="flex items-center m-5">
                    <label for="name" class="text-lg m-2">Name</label>
                    <input id="name" class="border-2 m-2 w-60 h-8" value={name} onChange={(event) => {name = event.target.value}} maxlength={80} required/>
                </div>
                <button class="inline-flex items-center border-2 rounded m-4 p-3 bg-neutral-400">Update Playlist</button>
            </form>
        </div>
    )
}

export default UpdatePlaylistModal;

// The part of Firestore the generator's adapters use, in memory, for their
// tests. Queries filter, order, limit and select as Firestore does, so an
// adapter that drops one of them is caught.
import {
  DocumentData,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

interface Query {
  where?: [string, unknown];
  orderBy?: [string, "asc" | "desc"];
  limit?: number;
  select?: string[];
}

/**
 * Documents by path. Each commit (a set outside a transaction, or a
 * transaction) gets the next day of November 2026 as its time, which
 * server timestamps take. A transaction applies its writes only once its
 * function has finished; a `create` of an existing document fails it
 * whole.
 */
export function fakeFirestore(
  documents: { [path: string]: DocumentData } = {},
) {
  const data = new Map(Object.entries(documents));
  let commits = 0;
  const commit = (writes: [string, DocumentData][]) => {
    const at = Timestamp.fromMillis(Date.UTC(2026, 10, ++commits));
    for (const [path, document] of writes) {
      data.set(
        path,
        Object.fromEntries(
          Object.entries(document).map(([k, v]) => [
            k,
            v instanceof FieldValue ? at : v,
          ]),
        ),
      );
    }
  };
  const snapshot = (path: string, fields?: string[]) => {
    const document = data.get(path);
    return {
      id: path.split("/").at(-1) ?? "",
      exists: document !== undefined,
      data: () =>
        document === undefined || fields === undefined
          ? document
          : Object.fromEntries(fields.map((f) => [f, document[f]])),
    };
  };
  const doc = (path: string) => ({
    path,
    get: async () => snapshot(path),
    collection: (name: string) => collection(`${path}/${name}`),
  });
  const collection = (path: string, query: Query = {}) => ({
    doc: (id: string) => doc(`${path}/${id}`),
    where: (field: string, _op: "==", value: unknown) =>
      collection(path, { ...query, where: [field, value] }),
    orderBy: (field: string, direction: "asc" | "desc" = "asc") =>
      collection(path, { ...query, orderBy: [field, direction] }),
    limit: (limit: number) => collection(path, { ...query, limit }),
    select: (...fields: string[]) =>
      collection(path, { ...query, select: fields }),
    async get() {
      let paths = [...data.keys()].filter(
        (p) =>
          p.startsWith(`${path}/`) && !p.slice(path.length + 1).includes("/"),
      );
      const where = query.where;
      if (where) {
        paths = paths.filter((p) => data.get(p)?.[where[0]] === where[1]);
      }
      const order = query.orderBy;
      if (order) {
        const [field, direction] = order;
        const sign = direction === "desc" ? -1 : 1;
        const value = (p: string) => data.get(p)?.[field] as number;
        paths.sort((a, b) => sign * (value(a) - value(b)));
      }
      return {
        docs: paths
          .slice(0, query.limit)
          .map((p) => snapshot(p, query.select)),
      };
    },
  });
  type Ref = ReturnType<typeof doc>;
  const db = {
    doc,
    collection: (path: string) => collection(path),
    async runTransaction<T>(run: (transaction: unknown) => Promise<T>) {
      const writes: [string, DocumentData][] = [];
      const created: string[] = [];
      const result = await run({
        get: async (ref: Ref) => snapshot(ref.path),
        set(ref: Ref, document: DocumentData) {
          writes.push([ref.path, document]);
        },
        create(ref: Ref, document: DocumentData) {
          created.push(ref.path);
          writes.push([ref.path, document]);
        },
      });
      if (created.some((path) => data.has(path))) {
        throw Object.assign(new Error("ALREADY_EXISTS"), { code: 6 });
      }
      commit(writes);
      return result;
    },
  };
  return {
    db: db as unknown as Firestore,
    data,
    /** Sets [path] as a write outside the functions would. */
    set: (path: string, document: DocumentData) => commit([[path, document]]),
  };
}
